import Accelerate
import Combine
import CoreMedia
import QuartzCore
import ScreenCaptureKit

/// The condensed control signals the plasma shader consumes. Each is 0…1,
/// smoothed with its own attack/decay so bass moves slow and heavy while
/// highs flicker.
struct AudioSignals: Equatable {
    var bass: Float = 0
    var mid: Float = 0
    var high: Float = 0
    var level: Float = 0
    /// CACurrentMediaTime of the last detected bass onset ("the drop hit").
    var onsetTime: Double = -1000
    /// How hard that onset hit, 0…1.
    var onsetStrength: Float = 0
}

/// Captures Spotify's audio output with ScreenCaptureKit and runs it through
/// an FFT. The spectrum is never displayed directly — it is condensed into
/// AudioSignals that steer the procedural plasma simulation. Capture is
/// filtered to the Spotify app when it's running, so other system sounds
/// don't pollute the picture.
final class AudioVisualizerEngine: NSObject, ObservableObject, SCStreamDelegate, SCStreamOutput {
    static let bandCount = 48
    static let waveformCount = 120

    @Published private(set) var signals = AudioSignals()
    /// Raw downsampled waveform of the latest FFT window — debug overlay only.
    @Published private(set) var waveform = [Float](repeating: 0, count: AudioVisualizerEngine.waveformCount)

    /// Fired once when capture can't start — almost always the Screen &
    /// System Audio Recording permission.
    var onCaptureProblem: (() -> Void)?

    private let sampleQueue = DispatchQueue(label: "dhun.visualizer.audio")
    private var stream: SCStream?
    private var isRunning = false
    private var reportedProblem = false
    private var buffersReceived = 0
    private var analyzeCount = 0
    private var forceDisplayWide = false

    private let fftSize = 1024
    private let log2n = vDSP_Length(10)
    private lazy var fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    private var hannWindow: [Float]
    private var ringBuffer = [Float]()
    private var smoothedSignals = AudioSignals()
    private var slowBassAverage: Float = 0

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
        // Re-surface permission problems on every session, not once per launch.
        reportedProblem = false
        Task { await self.startCapture() }
    }

    func stop() {
        isRunning = false
        let departing = stream
        stream = nil
        Task { try? await departing?.stopCapture() }
        sampleQueue.async {
            self.ringBuffer.removeAll()
            self.smoothedSignals = AudioSignals()
            self.slowBassAverage = 0
        }
        DispatchQueue.main.async {
            self.signals = AudioSignals()
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
            let useAppFilter = !spotify.isEmpty && !forceDisplayWide
            let filter: SCContentFilter
            if useAppFilter {
                filter = SCContentFilter(display: display, including: spotify, exceptingWindows: [])
            } else {
                filter = SCContentFilter(display: display, excludingWindows: [])
            }

            let newStream = SCStream(filter: filter, configuration: config, delegate: self)
            try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            try await newStream.startCapture()
            if isRunning {
                stream = newStream
                NSLog("Visualizer capture started (appFilter=\(useAppFilter))")
                if useAppFilter {
                    watchForSilentCapture()
                }
            } else {
                try? await newStream.stopCapture()
            }
        } catch {
            NSLog("Visualizer audio capture failed: \(error.localizedDescription)")
            reportProblem()
        }
    }

    /// The app-filtered capture can start "successfully" yet deliver nothing
    /// (e.g. when the audio actually comes from a helper process the filter
    /// doesn't match). If no buffers arrive shortly after starting, retry
    /// with display-wide capture, which hears everything.
    private func watchForSilentCapture() {
        sampleQueue.async { self.buffersReceived = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, self.isRunning else { return }
            self.sampleQueue.async {
                guard self.buffersReceived == 0 else { return }
                NSLog("Visualizer: app-filtered capture is silent; falling back to display-wide capture")
                DispatchQueue.main.async {
                    guard self.isRunning else { return }
                    self.forceDisplayWide = true
                    let departing = self.stream
                    self.stream = nil
                    Task {
                        try? await departing?.stopCapture()
                        await self.startCapture()
                    }
                }
            }
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
        buffersReceived += 1
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

        // Condense the spectrum into control signals. Bass gets slow, heavy
        // smoothing; highs stay twitchy so fine detail can flicker.
        func bandAverage(_ range: Range<Int>) -> Float {
            var sum: Float = 0
            for i in range { sum += newBands[i] }
            return sum / Float(range.count)
        }
        // Bass onset: the instantaneous bass jumping well above its own
        // long-term average, with a cooldown so one drop fires one event.
        // Ratio-based threshold so it still fires on heavily compressed
        // masters (EDM) where bass never fully drops out between kicks.
        let bassNow = bandAverage(0..<9)
        slowBassAverage = slowBassAverage * 0.98 + bassNow * 0.02
        let now = CACurrentMediaTime()
        if bassNow > 0.35,
           bassNow > slowBassAverage * 1.28 + 0.06,
           now - smoothedSignals.onsetTime > 0.6 {
            smoothedSignals.onsetTime = now
            smoothedSignals.onsetStrength = min(bassNow * 1.25, 1.0)
            NSLog("Visualizer: bass onset, strength=%.2f", smoothedSignals.onsetStrength)
        }

        analyzeCount += 1
        if analyzeCount % 250 == 1 {
            NSLog("Visualizer audio: level=%.2f bass=%.2f slowBass=%.2f",
                  smoothedSignals.level, smoothedSignals.bass, slowBassAverage)
        }

        smoothedSignals.bass = smooth(smoothedSignals.bass, bandAverage(0..<9), attack: 0.40, decay: 0.93)
        smoothedSignals.mid = smooth(smoothedSignals.mid, bandAverage(10..<32), attack: 0.50, decay: 0.86)
        smoothedSignals.high = smooth(smoothedSignals.high, bandAverage(34..<Self.bandCount), attack: 0.70, decay: 0.72)
        smoothedSignals.level = smooth(smoothedSignals.level, bandAverage(0..<Self.bandCount), attack: 0.35, decay: 0.95)

        let step = max(1, samples.count / Self.waveformCount)
        var wave = [Float](repeating: 0, count: Self.waveformCount)
        for i in 0..<Self.waveformCount {
            wave[i] = samples[min(i * step, samples.count - 1)]
        }

        let signalsCopy = smoothedSignals
        DispatchQueue.main.async {
            self.signals = signalsCopy
            self.waveform = wave
        }
    }

    private func smooth(_ current: Float, _ target: Float, attack: Float, decay: Float) -> Float {
        target > current ? current + (target - current) * attack : current * decay
    }
}
