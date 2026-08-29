import Accelerate
import Combine
import CoreMedia
import ScreenCaptureKit

enum VisualizerStyle: String, CaseIterable, Hashable {
    case bars
    case wave

    var label: String {
        switch self {
        case .bars: return "Spectrum bars"
        case .wave: return "Waveform"
        }
    }
}

/// Captures Spotify's audio output with ScreenCaptureKit and runs it through
/// an FFT to produce smoothed spectrum bands and a waveform for the ambient
/// visualizer. Capture is filtered to the Spotify app when it's running, so
/// other system sounds don't pollute the picture.
final class AudioVisualizerEngine: NSObject, ObservableObject, SCStreamDelegate, SCStreamOutput {
    static let bandCount = 48
    private static let waveformCount = 240

    @Published private(set) var bands = [Float](repeating: 0, count: AudioVisualizerEngine.bandCount)
    @Published private(set) var waveform = [Float](repeating: 0, count: AudioVisualizerEngine.waveformCount)

    /// Fired once when capture can't start — almost always the Screen &
    /// System Audio Recording permission.
    var onCaptureProblem: (() -> Void)?

    private let sampleQueue = DispatchQueue(label: "dhun.visualizer.audio")
    private var stream: SCStream?
    private var isRunning = false
    private var reportedProblem = false

    private let fftSize = 1024
    private let log2n = vDSP_Length(10)
    private lazy var fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    private var hannWindow: [Float]
    private var ringBuffer = [Float]()
    private var smoothedBands = [Float](repeating: 0, count: AudioVisualizerEngine.bandCount)

    override init() {
        hannWindow = [Float](repeating: 0, count: fftSize)
        super.init()
        vDSP_hann_window(&hannWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        Task { await self.startCapture() }
    }

    func stop() {
        isRunning = false
        let departing = stream
        stream = nil
        Task { try? await departing?.stopCapture() }
        sampleQueue.async {
            self.ringBuffer.removeAll()
            self.smoothedBands = [Float](repeating: 0, count: Self.bandCount)
        }
        DispatchQueue.main.async {
            self.bands = [Float](repeating: 0, count: Self.bandCount)
            self.waveform = [Float](repeating: 0, count: Self.waveformCount)
        }
    }

    private func startCapture() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard isRunning, let display = content.displays.first else { return }

            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48_000
            config.channelCount = 1
            // A video stream is part of the deal; keep it as close to free
            // as possible — 2×2 pixels at 1 fps, frames simply dropped.
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            config.showsCursor = false

            let spotify = content.applications.filter { $0.bundleIdentifier == "com.spotify.client" }
            let filter: SCContentFilter
            if spotify.isEmpty {
                filter = SCContentFilter(display: display, excludingWindows: [])
            } else {
                filter = SCContentFilter(display: display, including: spotify, exceptingWindows: [])
            }

            let newStream = SCStream(filter: filter, configuration: config, delegate: self)
            try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            try await newStream.startCapture()
            if isRunning {
                stream = newStream
            } else {
                try? await newStream.stopCapture()
            }
        } catch {
            reportProblem()
        }
    }

    private func reportProblem() {
        DispatchQueue.main.async {
            guard !self.reportedProblem else { return }
            self.reportedProblem = true
            self.onCaptureProblem?()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard isRunning else { return }
        self.stream = nil
        reportProblem()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        var incoming = [Float]()
        try? sampleBuffer.withAudioBufferList { bufferList, _ in
            guard let buffer = bufferList.first, let data = buffer.mData else { return }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.stride
            incoming = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count))
        }
        guard !incoming.isEmpty else { return }

        ringBuffer.append(contentsOf: incoming)
        let overflow = ringBuffer.count - fftSize
        if overflow > 0 {
            ringBuffer.removeFirst(overflow)
        }
        guard ringBuffer.count == fftSize else { return }
        analyze(ringBuffer)
    }

    private func analyze(_ samples: [Float]) {
        guard let fftSetup else { return }

        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(samples, 1, hannWindow, 1, &windowed, 1, vDSP_Length(fftSize))

        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        windowed.withUnsafeBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPointer in
                real.withUnsafeMutableBufferPointer { realBuffer in
                    imag.withUnsafeMutableBufferPointer { imagBuffer in
                        var split = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imagBuffer.baseAddress!)
                        vDSP_ctoz(complexPointer, 2, &split, 1, vDSP_Length(fftSize / 2))
                        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                        vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
                    }
                }
            }
        }

        // Log-spaced bands covering roughly 45 Hz – 16 kHz.
        let minBin = 1.0
        let maxBin = 340.0
        var newBands = [Float](repeating: 0, count: Self.bandCount)
        for band in 0..<Self.bandCount {
            let lo = Int(minBin * pow(maxBin / minBin, Double(band) / Double(Self.bandCount)))
            let hi = max(lo + 1, Int(minBin * pow(maxBin / minBin, Double(band + 1) / Double(Self.bandCount))))
            var sum: Float = 0
            for bin in lo..<min(hi, magnitudes.count) {
                sum += magnitudes[bin]
            }
            let average = sum / Float(max(hi - lo, 1))
            let decibels = 20 * log10(average + 1e-9)
            newBands[band] = min(max((decibels + 50) / 45, 0), 1)
        }

        // Fast attack, slow decay — the classic falling-bars feel.
        for i in 0..<Self.bandCount {
            let target = newBands[i]
            let current = smoothedBands[i]
            smoothedBands[i] = target > current
                ? current + (target - current) * 0.55
                : current * 0.86
        }

        let step = max(1, fftSize / Self.waveformCount)
        var wave = [Float](repeating: 0, count: Self.waveformCount)
        for i in 0..<Self.waveformCount {
            wave[i] = samples[min(i * step, fftSize - 1)]
        }

        let bandsCopy = smoothedBands
        DispatchQueue.main.async {
            self.bands = bandsCopy
            self.waveform = wave
        }
    }
}
