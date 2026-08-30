// Dhun visualizer shader library.
// Compiled at runtime with device.makeLibrary(source:) — no offline Metal
// toolchain required. Every visualizer consumes the same VizUniforms: four
// smoothed audio signals plus two tint colors.

#include <metal_stdlib>
using namespace metal;

struct VizUniforms {
    float2 resolution;
    float time;
    float bass;
    float mid;
    float high;
    float level;
    float beatAge;      // seconds since the last bass onset
    float beatStrength; // how hard it hit, 0…1
    float beatPulse;    // CPU-smoothed blast envelope: rises fast, eases back
    float2 pad2;
    float4 colorA;
    float4 colorB;
};

struct FSQVertexOut {
    float4 position [[position]];
};

vertex FSQVertexOut fsqVertex(uint vid [[vertex_id]]) {
    float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    FSQVertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    return out;
}

constexpr sampler linearSampler(address::clamp_to_edge, filter::linear);

// ---------------------------------------------------------------- noise ----

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float2 hash22(float2 p) {
    float n = sin(dot(p, float2(41.0, 289.0)));
    return fract(float2(262144.0, 32768.0) * n);
}

static float hash31(float3 p) {
    p = fract(p * 0.3183099 + float3(0.1, 0.2, 0.3));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
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

static float vnoise3(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);
    float n000 = hash31(i);
    float n100 = hash31(i + float3(1, 0, 0));
    float n010 = hash31(i + float3(0, 1, 0));
    float n110 = hash31(i + float3(1, 1, 0));
    float n001 = hash31(i + float3(0, 0, 1));
    float n101 = hash31(i + float3(1, 0, 1));
    float n011 = hash31(i + float3(0, 1, 1));
    float n111 = hash31(i + float3(1, 1, 1));
    float nx00 = mix(n000, n100, u.x);
    float nx10 = mix(n010, n110, u.x);
    float nx01 = mix(n001, n101, u.x);
    float nx11 = mix(n011, n111, u.x);
    float nxy0 = mix(nx00, nx10, u.y);
    float nxy1 = mix(nx01, nx11, u.y);
    return mix(nxy0, nxy1, u.z);
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

static float fbmCheap(float2 p) {
    float value = 0.0;
    float amp = 0.5;
    float2x2 rot = float2x2(0.80, 0.60, -0.60, 0.80);
    for (int i = 0; i < 3; i++) {
        value += amp * vnoise(p);
        p = rot * p * 2.02;
        amp *= 0.5;
    }
    return value;
}

static float fbm3(float3 p) {
    float value = 0.0;
    float amp = 0.55;
    for (int i = 0; i < 3; i++) {
        value += amp * vnoise3(p);
        p = p * 2.03 + float3(1.7, 9.2, 3.1);
        amp *= 0.5;
    }
    return value;
}

static float2 curl2(float2 p) {
    float e = 0.15;
    float n1 = fbmCheap(p + float2(0.0, e));
    float n2 = fbmCheap(p - float2(0.0, e));
    float n3 = fbmCheap(p + float2(e, 0.0));
    float n4 = fbmCheap(p - float2(e, 0.0));
    return float2(n1 - n2, n4 - n3) / (2.0 * e);
}

// --------------------------------------------------------------- plasma ----

fragment float4 plasmaFragment(FSQVertexOut in [[stage_in]],
                               constant VizUniforms& u [[buffer(0)]]) {
    float2 p = (in.position.xy - 0.5 * u.resolution) / u.resolution.y;
    float t = u.time * 0.12;

    float bass = u.bass;
    float mid = u.mid;
    float high = u.high;
    float level = u.level;

    p *= 1.55 - 0.35 * bass;

    float2 drift = float2(0.35 * t, -0.22 * t);
    float2 q = float2(fbm(p + drift),
                      fbm(p + drift + float2(5.2, 1.3)));
    float turbulence = 1.1 + 1.6 * mid;
    float speed = 0.9 + 1.4 * bass;
    float2 r = float2(fbm(p + turbulence * q + float2(1.7, 9.2) + 0.55 * t * speed),
                      fbm(p + turbulence * q + float2(8.3, 2.8) - 0.45 * t * speed));
    float field = fbm(p + 1.6 * r);

    float cloud = smoothstep(0.28, 0.85, field);
    cloud = pow(cloud, 1.7 - 0.6 * bass);

    float phase = (field + 0.4 * r.x) * (7.0 + 9.0 * mid) + t * 2.2;
    float tendril = exp(-fabs(sin(phase)) * (9.0 - 4.5 * mid));
    tendril *= smoothstep(0.18, 0.62, field);

    float phase2 = (r.y + 0.6 * q.x) * (16.0 + 14.0 * high) - t * 3.1;
    float filament = exp(-fabs(sin(phase2)) * 14.0);
    filament *= smoothstep(0.32, 0.72, field) * (0.25 + 1.4 * high);

    float sparkle = vnoise(p * 24.0 + float2(t * 21.0, -t * 17.0));
    sparkle = pow(sparkle, 7.0) * high * 1.8 * cloud;

    float3 tintA = u.colorA.rgb;
    float3 tintB = u.colorB.rgb;
    float3 color = tintA * 0.10;
    color += tintA * cloud * (0.50 + 0.75 * level);
    color += tintB * tendril * (0.45 + 0.75 * mid + 0.35 * bass);
    color += mix(tintB, float3(1.0), 0.55) * filament;
    color += mix(tintB, float3(1.0), 0.75) * sparkle;

    float core = smoothstep(0.74, 0.97, field);
    color += mix(tintA, float3(1.0), 0.50) * core * (0.25 + 0.9 * bass);

    float vignette = 1.0 - 0.5 * dot(p, p);
    color *= max(vignette, 0.0);
    color *= 0.80 + 0.55 * level;

    color = 1.0 - exp(-color * 2.1);
    return float4(color, 1.0);
}

// --------------------------------------------------------------- nebula ----

fragment float4 nebulaFragment(FSQVertexOut in [[stage_in]],
                               constant VizUniforms& u [[buffer(0)]]) {
    float2 p = (in.position.xy - 0.5 * u.resolution) / u.resolution.y;
    float t = u.time;

    float3 ro = float3(0.0, 0.0, t * (0.30 + 0.75 * u.bass));
    float3 rd = normalize(float3(p, 1.15));
    float sway = 0.12 * sin(t * 0.09);
    float cs = cos(sway);
    float sn = sin(sway);
    rd.xy = float2(rd.x * cs - rd.y * sn, rd.x * sn + rd.y * cs);

    float3 color = u.colorA.rgb * 0.03;

    // Embedded starfield, twinkling with the highs.
    float star = pow(vnoise(p * 90.0 + float2(0.0, t * 0.4)), 22.0);
    color += float3(0.85, 0.92, 1.0) * star * (0.5 + 1.4 * u.high);

    float transmittance = 1.0;
    float travelled = 0.0;
    for (int i = 0; i < 40; i++) {
        float3 pos = ro + rd * (1.0 + travelled);
        float density = fbm3(pos * 0.55 + float3(0.0, t * 0.04, 0.0)) - (0.47 - 0.10 * u.mid);
        if (density > 0.0) {
            float d = min(density * 1.5, 1.0);
            float tone = clamp(pos.y * 0.5 + 0.5 + 0.3 * sin(t * 0.15), 0.0, 1.0);
            float3 local = mix(u.colorA.rgb, u.colorB.rgb, tone);
            color += transmittance * d * local * 0.15 * (0.6 + 0.9 * u.level);
            transmittance *= 1.0 - d * 0.35;
            if (transmittance < 0.05) break;
        }
        travelled += 0.18;
    }

    float core = exp(-dot(p, p) * 3.0);
    color += mix(u.colorB.rgb, float3(1.0), 0.4) * core * (0.08 + 0.5 * u.bass);

    color = 1.0 - exp(-color * 2.0);
    return float4(color, 1.0);
}

// ----------------------------------------------------------- ferrofluid ----

static float ferroSDF(float3 q, float t, float bass, float mid, float high) {
    float radius = 0.62 + 0.11 * bass;
    float3 n = normalize(q + float3(0.0001));
    float spikes = fbm3(n * (3.5 + 3.0 * mid) + float3(0.0, t * 0.15, 0.0));
    spikes = pow(max(spikes - 0.34, 0.0), 1.6);
    float amp = 0.08 + 0.45 * mid;
    float shimmer = 0.015 * high * vnoise3(n * 24.0 + float3(t * 2.0));
    return length(q) - radius - amp * spikes - shimmer;
}

fragment float4 ferroFragment(FSQVertexOut in [[stage_in]],
                              constant VizUniforms& u [[buffer(0)]]) {
    float2 p = (in.position.xy - 0.5 * u.resolution) / u.resolution.y;
    p.y = -p.y;
    float t = u.time;

    float3 ro = float3(0.0, 0.0, -2.3);
    float3 rd = normalize(float3(p, 1.6));

    float3 color = u.colorA.rgb * 0.06 * exp(-dot(p, p) * 1.4);

    float dist = 0.0;
    bool hit = false;
    float3 pos = ro;
    for (int i = 0; i < 64; i++) {
        pos = ro + rd * dist;
        float d = ferroSDF(pos, t, u.bass, u.mid, u.high);
        if (d < 0.002) { hit = true; break; }
        dist += d * 0.8;
        if (dist > 6.0) break;
    }

    if (hit) {
        float e = 0.005;
        float3 normal = normalize(float3(
            ferroSDF(pos + float3(e, 0, 0), t, u.bass, u.mid, u.high) - ferroSDF(pos - float3(e, 0, 0), t, u.bass, u.mid, u.high),
            ferroSDF(pos + float3(0, e, 0), t, u.bass, u.mid, u.high) - ferroSDF(pos - float3(0, e, 0), t, u.bass, u.mid, u.high),
            ferroSDF(pos + float3(0, 0, e), t, u.bass, u.mid, u.high) - ferroSDF(pos - float3(0, 0, e), t, u.bass, u.mid, u.high)));
        float3 lightDir = normalize(float3(0.6, 0.8, -0.5));
        float diffuse = max(dot(normal, lightDir), 0.0);
        float3 reflected = reflect(rd, normal);
        float specular = pow(max(dot(reflected, lightDir), 0.0), 42.0);
        float fresnel = pow(1.0 - max(dot(-rd, normal), 0.0), 3.0);
        float3 environment = mix(u.colorA.rgb * 0.25, u.colorB.rgb, clamp(reflected.y * 0.5 + 0.5, 0.0, 1.0));

        color = float3(0.015);
        color += environment * (0.15 + 0.55 * fresnel);
        color += u.colorB.rgb * fresnel * (0.45 + 0.8 * u.mid);
        color += float3(1.0) * specular * (0.5 + 0.9 * u.level);
        color += u.colorA.rgb * diffuse * 0.10;
    }

    color = 1.0 - exp(-color * 2.2);
    return float4(color, 1.0);
}

// --------------------------------------------------------------- aurora ----

fragment float4 auroraFragment(FSQVertexOut in [[stage_in]],
                               constant VizUniforms& u [[buffer(0)]]) {
    float2 uv = in.position.xy / u.resolution;
    float2 p = float2(uv.x * u.resolution.x / u.resolution.y, 1.0 - uv.y);
    float t = u.time;

    float3 color = float3(0.004, 0.006, 0.012);

    float star = pow(vnoise(p * 120.0), 24.0);
    color += float3(0.8, 0.9, 1.0) * star * (0.3 + 0.9 * u.high) * smoothstep(0.25, 0.8, p.y);

    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float sway = fbm(float2(p.x * 0.9 + fi * 3.7, t * (0.10 + 0.03 * fi))) * (0.8 + 1.4 * u.bass);
        float xw = p.x * 1.6 + sway + fi * 1.3 - t * 0.05;
        float ridge = fbm(float2(xw, fi * 9.1 + t * 0.15));
        float curtain = pow(clamp(ridge, 0.0, 1.0), 3.0 - 1.5 * u.mid);
        float y0 = p.y - 0.35 - 0.08 * fi;
        float vertical = smoothstep(0.02, 0.22, p.y) * exp(-y0 * y0 / (0.05 + 0.18 * curtain));
        float striation = 0.75 + 0.25 * vnoise(float2(xw * 30.0, p.y * 6.0 - t * 0.8));
        striation += 0.35 * u.high * vnoise(float2(xw * 80.0, t * 6.0));
        float3 tint = mix(u.colorB.rgb, u.colorA.rgb, clamp(p.y * 1.6 - 0.2, 0.0, 1.0));
        color += tint * curtain * vertical * striation * (0.35 + 0.55 * u.level) / (1.0 + fi * 0.6);
    }

    color = 1.0 - exp(-color * 2.4);
    return float4(color, 1.0);
}

// --------------------------------------------------- ink (feedback pass) ---

fragment float4 inkFragment(FSQVertexOut in [[stage_in]],
                            constant VizUniforms& u [[buffer(0)]],
                            texture2d<float> prev [[texture(0)]]) {
    float2 uv = in.position.xy / u.resolution;
    float2 p = (in.position.xy - 0.5 * u.resolution) / u.resolution.y;
    float t = u.time;
    float aspect = u.resolution.x / u.resolution.y;

    float2 flow = curl2(p * 2.2 + float2(0.0, t * 0.05)) * (0.0016 + 0.0050 * u.mid);
    flow.y -= 0.0006 + 0.0016 * u.bass; // buoyancy

    float3 color = prev.sample(linearSampler, uv + flow).rgb * 0.986;

    float2 auv = float2(uv.x * aspect, uv.y);
    float2 e1 = float2((0.5 + 0.30 * sin(t * 0.21)) * aspect, 0.55 + 0.25 * sin(t * 0.13 + 2.0));
    float2 e2 = float2((0.5 + 0.28 * sin(t * 0.17 + 4.0)) * aspect, 0.45 + 0.27 * sin(t * 0.23 + 1.0));
    float blob1 = exp(-dot(auv - e1, auv - e1) * 900.0);
    float blob2 = exp(-dot(auv - e2, auv - e2) * 1400.0);

    color += u.colorB.rgb * blob1 * (0.04 + 1.9 * u.bass * u.bass + 0.25 * u.level);
    color += u.colorA.rgb * blob2 * (0.03 + 1.2 * u.mid);
    color += mix(u.colorB.rgb, float3(1.0), 0.6) * blob2 * u.high * 0.6;

    return float4(clamp(color, 0.0, 6.0), 1.0);
}

// -------------------------------------------------- warp (feedback pass) ---

fragment float4 warpFragment(FSQVertexOut in [[stage_in]],
                             constant VizUniforms& u [[buffer(0)]],
                             texture2d<float> prev [[texture(0)]]) {
    float2 uv = in.position.xy / u.resolution;
    float2 p = (in.position.xy - 0.5 * u.resolution) / u.resolution.y;
    float t = u.time;

    float2 center = float2(0.5 + 0.08 * sin(t * 0.13), 0.5 + 0.06 * sin(t * 0.19 + 1.0));
    float2 d = uv - center;
    float angle = 0.0025 + 0.007 * u.mid;
    float zoom = 0.988 - 0.014 * u.bass;
    float ca = cos(angle);
    float sa = sin(angle);
    float2 rotated = float2(d.x * ca - d.y * sa, d.x * sa + d.y * ca);
    float3 color = prev.sample(linearSampler, center + rotated * zoom).rgb * 0.965;

    color += u.colorA.rgb * 0.0035;

    // Twinkling star cells; the feedback zoom stretches them into streaks.
    for (int i = 0; i < 3; i++) {
        float fi = float(i) + 1.0;
        float2 cell = floor(p * (22.0 * fi) + float2(fi * 13.7, fi * 7.9));
        float rnd = hash21(cell);
        float star = step(0.9965, rnd) * (0.5 + 0.5 * sin(t * (6.0 + fi * 2.0) + rnd * 40.0));
        float2 cellUV = fract(p * (22.0 * fi)) - 0.5;
        star *= exp(-dot(cellUV, cellUV) * 18.0);
        color += mix(u.colorB.rgb, float3(1.0), 0.5) * star * (0.30 + 1.3 * u.high) / fi;
    }

    float core = exp(-dot(p, p) * 5.0);
    color += mix(u.colorB.rgb, float3(1.0), 0.3) * core * 0.02 * (1.0 + 5.0 * u.bass);

    return float4(clamp(color, 0.0, 6.0), 1.0);
}

// ------------------------------------------------------- murmuration -------

struct Particle {
    float2 position;
    float2 velocity;
    float2 seed;
};

kernel void murmurationKernel(device Particle* particles [[buffer(0)]],
                              constant VizUniforms& u [[buffer(1)]],
                              uint id [[thread_position_in_grid]]) {
    Particle pt = particles[id];
    float aspect = u.resolution.x / u.resolution.y;
    float t = u.time;
    float dt = 1.0 / 60.0;

    float2 center = float2(aspect * 0.45 * sin(t * 0.20), 0.45 * sin(t * 0.13 + 1.3));

    float2 acc = (center - pt.position) * (0.55 + 1.6 * u.mid);
    acc += curl2(pt.position * 1.4 + float2(t * 0.06, 0.0)) * (0.9 + 2.2 * u.mid);
    acc += (hash22(pt.seed + fract(t) * 13.7) - 0.5) * (0.5 + 4.0 * u.high);

    float2 away = pt.position - center;
    float awayLen = max(length(away), 0.001);
    acc += (away / awayLen) * u.bass * u.bass * 2.4;

    float2 vel = pt.velocity + acc * dt;
    float speedLimit = 0.35 + 0.9 * u.level + 0.5 * u.bass;
    float spd = length(vel);
    if (spd > speedLimit) {
        vel *= speedLimit / spd;
    }
    float2 pos = pt.position + vel * dt;

    if (pos.x > aspect) pos.x = -aspect;
    if (pos.x < -aspect) pos.x = aspect;
    if (pos.y > 1.0) pos.y = -1.0;
    if (pos.y < -1.0) pos.y = 1.0;

    particles[id].position = pos;
    particles[id].velocity = vel;
}

struct ParticleVertexOut {
    float4 position [[position]];
    float speed;
    float pointSize [[point_size]];
};

vertex ParticleVertexOut particleVertex(const device Particle* particles [[buffer(0)]],
                                        constant VizUniforms& u [[buffer(1)]],
                                        uint vid [[vertex_id]]) {
    Particle pt = particles[vid];
    float aspect = u.resolution.x / u.resolution.y;
    ParticleVertexOut out;
    out.position = float4(pt.position.x / aspect, pt.position.y, 0.0, 1.0);
    out.speed = length(pt.velocity);
    out.pointSize = max(u.resolution.y * 0.0018 * (1.0 + 1.2 * u.level), 1.5);
    return out;
}

fragment float4 particleFragment(ParticleVertexOut in [[stage_in]],
                                 constant VizUniforms& u [[buffer(0)]],
                                 float2 pc [[point_coord]]) {
    float r = length(pc - 0.5);
    float alpha = smoothstep(0.5, 0.1, r);
    float3 color = mix(u.colorA.rgb, u.colorB.rgb, clamp(in.speed * 1.6, 0.0, 1.0));
    return float4(color * alpha * 0.35, 1.0);
}

// ------------------------------------------------- volumetric explosion ----
// Adapted for Dhun from "Volumetric explosion" by Duke
//   https://www.shadertoy.com/view/lsySzd
// itself based on Duke's "Supernova remnant" (MdKXzc), otaviogood's
// "Alien Beacon" (ld2SzK), and Shane's "Cheap Cloud Flythrough" (Xsc3R4).
// Original license: CC BY-NC-SA 3.0 Unported, as declared in the shader.
// Changes for Dhun: GLSL -> MSL; iChannel texture noise replaced with
// procedural value noise; keyboard/mouse/split-screen demo inputs removed;
// the looping `mod(iTime)` animation driver replaced with a bass-onset
// lifecycle on continuous (never-looping) time; colors routed through the
// app's tint system; brightness follows the audio level.

static float expNoise(float3 x) {
    return 1.0 - 0.82 * vnoise3(x);
}

static float expFbm(float3 p) {
    return expNoise(p * 0.06125) * 0.5
         + expNoise(p * 0.125) * 0.25
         + expNoise(p * 0.25) * 0.125
         + expNoise(p * 0.4) * 0.2;
}

// otaviogood's spiral noise; `amount` replaces the original looping
// -mod(iTime*0.2,-2.) term (0 = newborn dense fireball, 2 = dissolved).
static float spiralNoise(float3 p, float amount) {
    const float nudge = 4.0;
    const float normalizer = 1.0 / sqrt(1.0 + nudge * nudge);
    float n = amount;
    float iter = 2.0;
    for (int i = 0; i < 8; i++) {
        n += -fabs(sin(p.y * iter) + cos(p.x * iter)) / iter;
        p.xy += float2(p.y, -p.x) * nudge;
        p.xy *= normalizer;
        p.xz += float2(p.z, -p.x) * nudge;
        p.xz *= normalizer;
        iter *= 1.733733;
    }
    return n;
}

static float explosionMap(float3 p, float t, float dissolve, float radius) {
    // Continuous rotation (original used mouse + iTime).
    float a = t * 0.1;
    float2 xz = cos(a) * float2(p.x, p.z) + sin(a) * float2(p.z, -p.x);
    p = float3(xz.x, p.y, xz.y);

    float3 q = p / 0.5;
    // Slow domain drift so the structure churns forever without looping.
    float3 drift = float3(t * 0.05, t * 0.033, 0.0);
    float f = length(q) - radius;
    f += expFbm(q * 50.0 + drift * 12.0);
    f += spiralNoise(q.zxy * 0.4132 + 333.0 + drift, dissolve) * 3.0;
    return f * 0.5;
}

static float3 explosionColor(float density, float radius, float3 tintA, float3 tintB) {
    float3 hot = mix(tintB, float3(1.0, 0.95, 0.85), 0.30);
    float3 cool = tintA * 0.9;
    float3 result = mix(hot, cool, density);
    float3 colCenter = 8.0 * mix(float3(1.0), tintB, 0.45);
    float3 colEdge = 1.8 * mix(tintA, float3(0.5), 0.15);
    result *= mix(colCenter, colEdge, min((radius + 0.05) / 0.9, 1.15));
    return result;
}

static bool raySphere(float3 org, float3 dir, float boundSq,
                      thread float& nearHit, thread float& farHit) {
    float b = dot(dir, org);
    float c = dot(org, org) - boundSq;
    float delta = b * b - c;
    if (delta < 0.0) return false;
    float ds = sqrt(delta);
    nearHit = -b - ds;
    farHit = -b + ds;
    return farHit > 0.0;
}

fragment float4 explosionFragment(FSQVertexOut in [[stage_in]],
                                  constant VizUniforms& u [[buffer(0)]]) {
    float2 fragCoord = in.position.xy;
    float2 uv = fragCoord / u.resolution;
    float t = u.time;

    // Explosion lifecycle, driven by the last bass onset instead of a loop.
    float age = max(u.beatAge, 0.0);
    float strength = clamp(u.beatStrength, 0.0, 1.0);
    float energy = strength * exp(-age * 0.45);
    float dissolve = max(2.0 * (1.0 - exp(-age * 0.5)) - 0.3 * u.mid, 0.0);
    // Size follows the CPU-smoothed pulse: it expands quickly on a hit and
    // eases back down gradually — the radius travels, it never jumps.
    float pulse = clamp(u.beatPulse, 0.0, 1.5);
    float radius = 3.1 + 2.6 * pulse;
    float brightness = 0.22 + 0.50 * u.level + 2.1 * energy;

    float3 rd = normalize(float3((fragCoord - 0.5 * u.resolution) / u.resolution.y, 1.0));
    rd.y = -rd.y;
    float3 ro = float3(0.0, 0.0, -6.0);

    float ld = 0.0, td = 0.0, w = 0.0;
    float dcur = 1.0, tt = 0.0;
    const float h = 0.1;
    float4 sum = float4(0.0);
    float minDist = 0.0, maxDist = 0.0;

    float worldR = radius * 0.5;
    float boundSq = (worldR * 1.3) * (worldR * 1.3);

    float3 lightColor = mix(u.colorB.rgb, float3(1.0), 0.10) * (1.1 + 0.6 * u.high);

    if (raySphere(ro, rd, boundSq, minDist, maxDist)) {
        tt = minDist * step(tt, minDist);

        for (int i = 0; i < 72; i++) {
            float3 pos = ro + tt * rd;
            if (td > 0.9 || dcur < 0.12 * tt || tt > 10.0 || sum.a > 0.99 || tt > maxDist) break;

            float d = explosionMap(pos, t, dissolve, radius);
            d = max(d, 0.03);

            float3 ldst = float3(0.0) - pos;
            float lDist = max(length(ldst), 0.001);

            // Central bloom — this is the smoldering ember between hits.
            sum.rgb += lightColor / exp(lDist * lDist * lDist * 0.08) / 30.0;

            if (d < h) {
                ld = h - d;
                w = (1.0 - td) * ld;
                td += w + 1.0 / 200.0;
                float4 col = float4(explosionColor(td, lDist, u.colorA.rgb, u.colorB.rgb), td);
                sum += sum.a * float4(sum.rgb, 0.0) * 0.2 / lDist;
                col.a *= 0.2;
                col.rgb *= col.a;
                sum = sum + col * (1.0 - sum.a);
            }
            td += 1.0 / 70.0;

            // Procedural stand-in for the original's dither texture.
            float2 uvd = float2(uv.y * 120.0, -uv.x * 280.0 + 0.5 * sin(4.0 * t + uv.y * 480.0));
            d = fabs(d) * (0.8 + 0.08 * vnoise(uvd));

            tt += max(d * 0.08 * max(min(lDist, d), 2.0), 0.01);
            dcur = d;
        }

        sum *= 1.0 / exp(ld * 0.2) * 0.8;
        sum = clamp(sum, 0.0, 1.0);
        sum.xyz = sum.xyz * sum.xyz * (3.0 - 2.0 * sum.xyz);
    }

    float3 color = sum.xyz * brightness;

    // Vibrance: push chroma away from gray so the tints pop.
    float luma = dot(color, float3(0.299, 0.587, 0.114));
    color = max(mix(float3(luma), color, 1.45), 0.0);

    color = 1.0 - exp(-color * 2.3);
    return float4(color, 1.0);
}

// ------------------------------------------------------ utility passes -----

fragment float4 fadeFragment(FSQVertexOut in [[stage_in]],
                             constant VizUniforms& u [[buffer(0)]],
                             texture2d<float> prev [[texture(0)]]) {
    float2 uv = in.position.xy / u.resolution;
    float3 color = prev.sample(linearSampler, uv).rgb * 0.90;
    return float4(color, 1.0);
}

fragment float4 presentFragment(FSQVertexOut in [[stage_in]],
                                constant VizUniforms& u [[buffer(0)]],
                                texture2d<float> src [[texture(0)]]) {
    float2 uv = in.position.xy / u.resolution;
    float3 color = src.sample(linearSampler, uv).rgb;
    color = 1.0 - exp(-color * 1.5);
    return float4(color, 1.0);
}
