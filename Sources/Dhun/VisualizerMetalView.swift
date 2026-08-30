import MetalKit
import SwiftUI

/// The visualizers available in Ambient mode. All of them are generative
/// systems steered by the audio signals — never direct FFT drawings.
enum VisualizerMode: String, CaseIterable, Hashable {
    case none
    case plasma
    case nebula
    case ferrofluid
    case aurora
    case ink
    case warp
    case murmuration
    case explosion
    case moonwalk
    case cloudcanal
    case calmflow
    case movement
    case butterfly

    var label: String {
        switch self {
        case .none: return "None (blurred cover)"
        case .plasma: return "Ambience Plasma"
        case .nebula: return "Nebula"
        case .ferrofluid: return "Ferrofluid"
        case .aurora: return "Aurora"
        case .ink: return "Ink in Water"
        case .warp: return "Warp Field"
        case .murmuration: return "Murmuration"
        case .explosion: return "Volumetric Explosion"
        case .moonwalk: return "MoonWalk"
        case .cloudcanal: return "Cloud Canal"
        case .calmflow: return "Calm Flow"
        case .movement: return "Movement"
        case .butterfly: return "Butterfly"
        }
    }

    enum Kind {
        case fullscreen(String)
        case feedback(String)
        case particles
    }

    var kind: Kind {
        switch self {
        case .none, .plasma: return .fullscreen("plasmaFragment")
        case .nebula: return .fullscreen("nebulaFragment")
        case .ferrofluid: return .fullscreen("ferroFragment")
        case .aurora: return .fullscreen("auroraFragment")
        case .ink: return .feedback("inkFragment")
        case .warp: return .feedback("warpFragment")
        case .murmuration: return .particles
        case .explosion: return .fullscreen("explosionFragment")
        case .moonwalk: return .fullscreen("moonwalkFragment")
        case .cloudcanal: return .fullscreen("cloudcanalFragment")
        case .calmflow: return .fullscreen("calmflowFragment")
        case .movement: return .feedback("movementFragment")
        case .butterfly: return .fullscreen("butterflyFragment")
        }
    }

    /// Fraction of native resolution to render at. The heavy raymarchers
    /// render smaller and let the layer upscale — invisible for soft visuals.
    var renderScale: CGFloat {
        switch self {
        case .none, .plasma: return 1.0
        case .aurora: return 0.9
        case .nebula: return 0.55
        case .ferrofluid: return 0.6
        case .ink: return 0.7
        case .warp: return 0.75
        case .murmuration: return 0.8
        case .explosion: return 0.5
        case .moonwalk: return 0.55
        case .cloudcanal: return 0.5
        case .calmflow: return 1.0
        case .movement: return 0.75
        case .butterfly: return 1.0
        }
    }
}

/// Color moods shared by every visualizer: curated duotones, or tints pulled
/// live from the current album's palette (vibrance-boosted so muddy covers
/// still glow).
enum VisualizerColorScheme: String, CaseIterable, Hashable {
    case electricBlue
    case ember
    case aurora
    case violetStorm
    case album

    var label: String {
        switch self {
        case .electricBlue: return "Electric Blue (classic)"
        case .ember: return "Ember"
        case .aurora: return "Aurora"
        case .violetStorm: return "Violet Storm"
        case .album: return "Album colors"
        }
    }

    /// Returns (body, accent) tints for the shaders.
    func resolve(palette: Palette) -> (body: SIMD4<Float>, accent: SIMD4<Float>) {
        switch self {
        case .electricBlue:
            return (SIMD4(0.04, 0.22, 0.70, 1), SIMD4(0.16, 0.70, 1.00, 1))
        case .ember:
            return (SIMD4(0.55, 0.18, 0.03, 1), SIMD4(1.00, 0.62, 0.16, 1))
        case .aurora:
            return (SIMD4(0.02, 0.35, 0.22, 1), SIMD4(0.20, 0.95, 0.60, 1))
        case .violetStorm:
            return (SIMD4(0.28, 0.06, 0.55, 1), SIMD4(0.75, 0.35, 1.00, 1))
        case .album:
            let body = Self.simd(Self.vivid(palette.primary, minSaturation: 0.50, minBrightness: 0.75)) * 0.7
            let accent = Self.simd(Self.vivid(palette.secondary, minSaturation: 0.55, minBrightness: 0.95))
            return (SIMD4(body.x, body.y, body.z, 1), accent)
        }
    }

    private static func vivid(_ color: NSColor, minSaturation: CGFloat, minBrightness: CGFloat) -> NSColor {
        let c = color.usingColorSpace(.deviceRGB) ?? color
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        c.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: max(saturation, minSaturation), brightness: max(brightness, minBrightness), alpha: 1)
    }

    private static func simd(_ color: NSColor) -> SIMD4<Float> {
        let c = color.usingColorSpace(.deviceRGB) ?? color
        return SIMD4(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent), 1)
    }
}

/// One Metal view, three rendering strategies:
/// - fullscreen: a single procedural fragment pass straight to the drawable
/// - feedback: ping-pong accumulation textures (the frame feeds on its own
///   past — ink advection, warp streaks), then a present pass
/// - particles: a compute pass moves the flock, a fade pass keeps trails,
///   additive points render on top, then a present pass
/// Live render statistics for the debug overlay.
final class VisualizerStats: ObservableObject {
    @Published var fps: Double = 0
}

final class VisualizerMetalView: MTKView, MTKViewDelegate {
    weak var engine: AudioVisualizerEngine?
    weak var stats: VisualizerStats?
    var colorA = SIMD4<Float>(0.04, 0.22, 0.70, 1)
    var colorB = SIMD4<Float>(0.16, 0.70, 1.00, 1)

    private var frameCount = 0
    private var lastFPSStamp = CACurrentMediaTime()
    private var travel: Float = 0
    private var lastTravelStamp = CACurrentMediaTime()

    var mode: VisualizerMode = .plasma {
        didSet {
            if mode != oldValue { configureForMode() }
        }
    }

    private var library: MTLLibrary?
    private lazy var commandQueue = device?.makeCommandQueue()
    private let startTime = CACurrentMediaTime()

    private var drawablePipelines: [String: MTLRenderPipelineState] = [:]
    private var offscreenPipelines: [String: MTLRenderPipelineState] = [:]
    private var particlePipeline: MTLRenderPipelineState?
    private var computePipeline: MTLComputePipelineState?

    private var artworkTexture: MTLTexture?
    private weak var lastArtworkImage: NSImage?
    private lazy var textureLoader: MTKTextureLoader? = device.map { MTKTextureLoader(device: $0) }
    private lazy var fallbackArtTexture: MTLTexture? = {
        guard let device else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        var pixel: [UInt8] = [26, 26, 32, 255]
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &pixel, bytesPerRow: 4)
        return texture
    }()

    func setArtwork(_ image: NSImage?) {
        guard image !== lastArtworkImage else { return }
        lastArtworkImage = image
        guard let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let loader = textureLoader else {
            artworkTexture = nil
            return
        }
        artworkTexture = try? loader.newTexture(cgImage: cgImage, options: [.SRGB: false as NSNumber])
    }

    private var accumulationA: MTLTexture?
    private var accumulationB: MTLTexture?
    private var readFromA = true

    private var particleBuffer: MTLBuffer?
    private let particleCount = 14000

    // Must match the MSL VizUniforms layout exactly.
    private struct Uniforms {
        var resolution: SIMD2<Float>
        var time: Float
        var bass: Float
        var mid: Float
        var high: Float
        var level: Float
        var beatAge: Float
        var beatStrength: Float
        var travel: Float
        var pad2: SIMD2<Float> = .zero
        var colorA: SIMD4<Float>
        var colorB: SIMD4<Float>
    }

    private struct ParticleData {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var seed: SIMD2<Float>
    }

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        delegate = self
        preferredFramesPerSecond = 60
        framebufferOnly = true
        autoResizeDrawable = false
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        loadLibrary()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func loadLibrary() {
        guard let device,
              let url = Bundle.module.url(forResource: "Shaders", withExtension: "metal"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("Visualizer shaders missing from bundle")
            return
        }
        do {
            library = try device.makeLibrary(source: source, options: nil)
        } catch {
            NSLog("Visualizer shaders failed to build: \(error.localizedDescription)")
        }
    }

    // MARK: - Sizing & mode

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = (window?.backingScaleFactor ?? 2) * mode.renderScale
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        if abs(size.width - drawableSize.width) > 1 || abs(size.height - drawableSize.height) > 1 {
            drawableSize = size
        }
    }

    private func configureForMode() {
        destroyAccumulation()
        if case .particles = mode.kind {
            seedParticles()
        }
        updateDrawableSize()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        destroyAccumulation()
    }

    // MARK: - Pipelines

    private func fullscreenPipeline(fragment: String, offscreen: Bool) -> MTLRenderPipelineState? {
        var cache = offscreen ? offscreenPipelines : drawablePipelines
        if let cached = cache[fragment] { return cached }
        guard let device, let library else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "fsqVertex")
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        descriptor.colorAttachments[0].pixelFormat = offscreen ? .rgba16Float : colorPixelFormat
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            NSLog("Pipeline failed for \(fragment)")
            return nil
        }
        cache[fragment] = pipeline
        if offscreen { offscreenPipelines = cache } else { drawablePipelines = cache }
        return pipeline
    }

    private func ensureParticlePipeline() -> MTLRenderPipelineState? {
        if let particlePipeline { return particlePipeline }
        guard let device, let library else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "particleVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "particleFragment")
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
        particlePipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
        return particlePipeline
    }

    private func ensureComputePipeline() -> MTLComputePipelineState? {
        if let computePipeline { return computePipeline }
        guard let device, let library,
              let kernel = library.makeFunction(name: "murmurationKernel") else { return nil }
        computePipeline = try? device.makeComputePipelineState(function: kernel)
        return computePipeline
    }

    // MARK: - Resources

    private func destroyAccumulation() {
        accumulationA = nil
        accumulationB = nil
        readFromA = true
    }

    private func ensureAccumulation() -> (read: MTLTexture, write: MTLTexture)? {
        let width = Int(drawableSize.width)
        let height = Int(drawableSize.height)
        guard width > 0, height > 0, let device, let commandQueue else { return nil }

        if accumulationA == nil || accumulationA!.width != width || accumulationA!.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            guard let a = device.makeTexture(descriptor: descriptor),
                  let b = device.makeTexture(descriptor: descriptor) else { return nil }
            accumulationA = a
            accumulationB = b
            readFromA = true

            // Clear both so feedback starts from black.
            if let buffer = commandQueue.makeCommandBuffer() {
                for texture in [a, b] {
                    let pass = MTLRenderPassDescriptor()
                    pass.colorAttachments[0].texture = texture
                    pass.colorAttachments[0].loadAction = .clear
                    pass.colorAttachments[0].storeAction = .store
                    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
                    buffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
                }
                buffer.commit()
            }
        }
        guard let a = accumulationA, let b = accumulationB else { return nil }
        return readFromA ? (a, b) : (b, a)
    }

    private func seedParticles() {
        guard let device else { return }
        let aspect = Float(max(bounds.width / max(bounds.height, 1), 0.5))
        var particles = [ParticleData]()
        particles.reserveCapacity(particleCount)
        for _ in 0..<particleCount {
            particles.append(ParticleData(
                position: SIMD2(Float.random(in: -aspect...aspect), Float.random(in: -1...1)),
                velocity: SIMD2(Float.random(in: -0.1...0.1), Float.random(in: -0.1...0.1)),
                seed: SIMD2(Float.random(in: 0...100), Float.random(in: 0...100))
            ))
        }
        particleBuffer = device.makeBuffer(
            bytes: particles,
            length: MemoryLayout<ParticleData>.stride * particleCount,
            options: .storageModeShared
        )
    }

    private func makeUniforms() -> Uniforms {
        let signals = engine?.signals ?? AudioSignals()
        let now = CACurrentMediaTime()

        // Integrated flight distance: speed follows the music, position
        // stays continuous so there are never jumps.
        let dt = Float(min(max(now - lastTravelStamp, 0), 0.1))
        lastTravelStamp = now
        travel += dt * (8.0 + 30.0 * signals.level + 22.0 * signals.bass)

        return Uniforms(
            resolution: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
            time: Float(now - startTime),
            bass: signals.bass,
            mid: signals.mid,
            high: signals.high,
            level: signals.level,
            beatAge: Float(min(max(now - signals.onsetTime, 0), 999)),
            beatStrength: signals.onsetStrength,
            travel: travel,
            colorA: colorA,
            colorB: colorB
        )
    }

    // MARK: - Drawing

    func draw(in view: MTKView) {
        guard mode != .none,
              let commandQueue,
              let drawable = currentDrawable else { return }
        var uniforms = makeUniforms()
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        switch mode.kind {
        case .fullscreen(let fragment):
            guard let pipeline = fullscreenPipeline(fragment: fragment, offscreen: false),
                  let pass = currentRenderPassDescriptor,
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            var bandsCopy = engine?.bands ?? []
            if bandsCopy.count != AudioVisualizerEngine.bandCount {
                bandsCopy = [Float](repeating: 0, count: AudioVisualizerEngine.bandCount)
            }
            bandsCopy.withUnsafeBytes { raw in
                encoder.setFragmentBytes(raw.baseAddress!, length: raw.count, index: 1)
            }
            encoder.setFragmentTexture(artworkTexture ?? fallbackArtTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()

        case .feedback(let fragment):
            guard let textures = ensureAccumulation(),
                  let update = fullscreenPipeline(fragment: fragment, offscreen: true),
                  let present = fullscreenPipeline(fragment: "presentFragment", offscreen: false) else { return }

            let updatePass = MTLRenderPassDescriptor()
            updatePass.colorAttachments[0].texture = textures.write
            updatePass.colorAttachments[0].loadAction = .dontCare
            updatePass.colorAttachments[0].storeAction = .store
            guard let updateEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: updatePass) else { return }
            updateEncoder.setRenderPipelineState(update)
            updateEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            var bandsCopy = engine?.bands ?? []
            if bandsCopy.count != AudioVisualizerEngine.bandCount {
                bandsCopy = [Float](repeating: 0, count: AudioVisualizerEngine.bandCount)
            }
            bandsCopy.withUnsafeBytes { raw in
                updateEncoder.setFragmentBytes(raw.baseAddress!, length: raw.count, index: 1)
            }
            updateEncoder.setFragmentTexture(textures.read, index: 0)
            updateEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            updateEncoder.endEncoding()

            guard let presentPass = currentRenderPassDescriptor,
                  let presentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: presentPass) else { return }
            presentEncoder.setRenderPipelineState(present)
            presentEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            presentEncoder.setFragmentTexture(textures.write, index: 0)
            presentEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            presentEncoder.endEncoding()

            readFromA.toggle()

        case .particles:
            if particleBuffer == nil { seedParticles() }
            guard let textures = ensureAccumulation(),
                  let compute = ensureComputePipeline(),
                  let fade = fullscreenPipeline(fragment: "fadeFragment", offscreen: true),
                  let points = ensureParticlePipeline(),
                  let present = fullscreenPipeline(fragment: "presentFragment", offscreen: false),
                  let particleBuffer else { return }

            guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
            computeEncoder.setComputePipelineState(compute)
            computeEncoder.setBuffer(particleBuffer, offset: 0, index: 0)
            computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            computeEncoder.dispatchThreads(
                MTLSize(width: particleCount, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1)
            )
            computeEncoder.endEncoding()

            let trailPass = MTLRenderPassDescriptor()
            trailPass.colorAttachments[0].texture = textures.write
            trailPass.colorAttachments[0].loadAction = .dontCare
            trailPass.colorAttachments[0].storeAction = .store
            guard let trailEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: trailPass) else { return }
            trailEncoder.setRenderPipelineState(fade)
            trailEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            trailEncoder.setFragmentTexture(textures.read, index: 0)
            trailEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

            trailEncoder.setRenderPipelineState(points)
            trailEncoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
            trailEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            trailEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            trailEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount)
            trailEncoder.endEncoding()

            guard let presentPass = currentRenderPassDescriptor,
                  let presentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: presentPass) else { return }
            presentEncoder.setRenderPipelineState(present)
            presentEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            presentEncoder.setFragmentTexture(textures.write, index: 0)
            presentEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            presentEncoder.endEncoding()

            readFromA.toggle()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()

        frameCount += 1
        let now = CACurrentMediaTime()
        if now - lastFPSStamp >= 1.0 {
            stats?.fps = Double(frameCount) / (now - lastFPSStamp)
            frameCount = 0
            lastFPSStamp = now
        }
    }
}

struct MetalVisualization: NSViewRepresentable {
    let engine: AudioVisualizerEngine
    let mode: VisualizerMode
    let colorA: SIMD4<Float>
    let colorB: SIMD4<Float>
    var stats: VisualizerStats? = nil
    var artwork: NSImage? = nil

    func makeNSView(context: Context) -> VisualizerMetalView {
        let view = VisualizerMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.engine = engine
        view.stats = stats
        view.mode = mode
        view.colorA = colorA
        view.colorB = colorB
        view.setArtwork(artwork)
        return view
    }

    func updateNSView(_ nsView: VisualizerMetalView, context: Context) {
        nsView.stats = stats
        nsView.mode = mode
        nsView.colorA = colorA
        nsView.colorB = colorB
        nsView.setArtwork(artwork)
    }
}
