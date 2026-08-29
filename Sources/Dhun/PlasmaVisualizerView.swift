import MetalKit
import SwiftUI

/// Full-screen procedural plasma inspired by the Windows Media Player
/// "Ambience" visualization: domain-warped noise clouds, luminous contour
/// tendrils, electrical filaments, and shimmer — a generative field that the
/// audio signals steer (turbulence, flow speed, scale, brightness, detail)
/// rather than a direct drawing of the FFT.
final class PlasmaVisualizerView: MTKView, MTKViewDelegate {
    weak var engine: AudioVisualizerEngine?

    private var pipeline: MTLRenderPipelineState?
    private lazy var commandQueue = device?.makeCommandQueue()
    private let startTime = CACurrentMediaTime()

    // Must match the MSL PlasmaUniforms layout exactly.
    private struct Uniforms {
        var resolution: SIMD2<Float>
        var time: Float
        var bass: Float
        var mid: Float
        var high: Float
        var level: Float
        var pad: Float = 0
    }

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        delegate = self
        preferredFramesPerSecond = 60
        framebufferOnly = true
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        buildPipeline()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildPipeline() {
        guard let device else { return }
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "plasmaVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "plasmaFragment")
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("Plasma shader failed to build: \(error.localizedDescription)")
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipeline,
              let drawable = currentDrawable,
              let descriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        let signals = engine?.signals ?? AudioSignals()
        var uniforms = Uniforms(
            resolution: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
            time: Float(CACurrentMediaTime() - startTime),
            bass: signals.bass,
            mid: signals.mid,
            high: signals.high,
            level: signals.level
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct PlasmaUniforms {
        float2 resolution;
        float time;
        float bass;
        float mid;
        float high;
        float level;
        float pad;
    };

    struct PlasmaVertexOut {
        float4 position [[position]];
    };

    vertex PlasmaVertexOut plasmaVertex(uint vid [[vertex_id]]) {
        float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        PlasmaVertexOut out;
        out.position = float4(positions[vid], 0.0, 1.0);
        return out;
    }

    static float hash21(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    static float vnoise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float a = hash21(i);
        float b = hash21(i + float2(1.0, 0.0));
        float c = hash21(i + float2(0.0, 1.0));
        float d = hash21(i + float2(1.0, 1.0));
        float2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }

    static float fbm(float2 p) {
        float value = 0.0;
        float amp = 0.5;
        float2x2 rot = float2x2(0.80, 0.60, -0.60, 0.80);
        for (int i = 0; i < 5; i++) {
            value += amp * vnoise(p);
            p = rot * p * 2.02;
            amp *= 0.5;
        }
        return value;
    }

    fragment float4 plasmaFragment(PlasmaVertexOut in [[stage_in]],
                                   constant PlasmaUniforms& u [[buffer(0)]]) {
        float2 p = (in.position.xy - 0.5 * u.resolution) / u.resolution.y;
        float t = u.time * 0.12;

        float bass = u.bass;
        float mid = u.mid;
        float high = u.high;
        float level = u.level;

        // Bass breathes the whole field: larger, slower masses on heavy lows.
        p *= 1.55 - 0.35 * bass;

        // Domain-warped flow: fbm fed through itself twice.
        float2 drift = float2(0.35 * t, -0.22 * t);
        float2 q = float2(fbm(p + drift),
                          fbm(p + drift + float2(5.2, 1.3)));
        float turbulence = 1.1 + 1.6 * mid;
        float speed = 0.9 + 1.4 * bass;
        float2 r = float2(fbm(p + turbulence * q + float2(1.7, 9.2) + 0.55 * t * speed),
                          fbm(p + turbulence * q + float2(8.3, 2.8) - 0.45 * t * speed));
        float field = fbm(p + 1.6 * r);

        // Cloud mass.
        float cloud = smoothstep(0.28, 0.85, field);
        cloud = pow(cloud, 1.7 - 0.6 * bass);

        // Luminous tendrils: glowing contour filaments of the warped field.
        float phase = (field + 0.4 * r.x) * (7.0 + 9.0 * mid) + t * 2.2;
        float tendril = exp(-fabs(sin(phase)) * (9.0 - 4.5 * mid));
        tendril *= smoothstep(0.18, 0.62, field);

        // Finer electrical filaments for the highs.
        float phase2 = (r.y + 0.6 * q.x) * (16.0 + 14.0 * high) - t * 3.1;
        float filament = exp(-fabs(sin(phase2)) * 14.0);
        filament *= smoothstep(0.32, 0.72, field) * (0.25 + 1.4 * high);

        // High-frequency shimmer inside the energy.
        float sparkle = vnoise(p * 24.0 + float2(t * 21.0, -t * 17.0));
        sparkle = pow(sparkle, 7.0) * high * 1.8 * cloud;

        // Color: deep night blue -> electric blue -> cyan -> white core.
        float3 color = float3(0.008, 0.02, 0.06);
        color += float3(0.04, 0.22, 0.70) * cloud * (0.50 + 0.75 * level);
        color += float3(0.16, 0.70, 1.00) * tendril * (0.45 + 0.75 * mid + 0.35 * bass);
        color += float3(0.55, 0.90, 1.00) * filament;
        color += float3(0.75, 0.97, 1.00) * sparkle;

        float core = smoothstep(0.74, 0.97, field);
        color += float3(0.35, 0.75, 1.00) * core * (0.25 + 0.9 * bass);

        // Soft vignette; keep a living floor during silence.
        float vignette = 1.0 - 0.5 * dot(p, p);
        color *= max(vignette, 0.0);
        color *= 0.80 + 0.55 * level;

        // Soft clip for the luminous look.
        color = 1.0 - exp(-color * 2.1);
        return float4(color, 1.0);
    }
    """
}

struct PlasmaVisualization: NSViewRepresentable {
    let engine: AudioVisualizerEngine

    func makeNSView(context: Context) -> PlasmaVisualizerView {
        let view = PlasmaVisualizerView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.engine = engine
        return view
    }

    func updateNSView(_ nsView: PlasmaVisualizerView, context: Context) {}
}
