#include <metal_stdlib>
using namespace metal;

struct WallpaperVertexOut {
    float4 position [[position]];
    float2 uv;
};

struct WallpaperUniforms {
    float time;
    float2 resolution;
    float2 mouse;
    uint effect;
};

vertex WallpaperVertexOut wallpaperVertex(uint vertexID [[vertex_id]]) {
    const float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    const float2 coordinates[3] = {
        float2(0.0, 0.0),
        float2(2.0, 0.0),
        float2(0.0, 2.0)
    };

    WallpaperVertexOut output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.uv = coordinates[vertexID];
    return output;
}

static float hash11(float value) {
    return fract(sin(value * 127.1) * 43758.5453);
}

static float2 hash21(float value) {
    return fract(sin(float2(value * 127.1, value * 311.7)) * 43758.5453);
}

static float3 palette(float value) {
    float3 a = float3(0.45, 0.48, 0.55);
    float3 b = float3(0.42, 0.38, 0.48);
    float3 c = float3(1.0, 1.0, 1.0);
    float3 d = float3(0.12, 0.32, 0.62);
    return a + b * cos(6.28318 * (c * value + d));
}

static float3 particleScene(float2 uv, constant WallpaperUniforms &u) {
    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float2 mouse = (u.mouse - 0.5) * float2(aspect, 1.0);
    float3 color = mix(float3(0.008, 0.012, 0.04),
                       float3(0.025, 0.055, 0.13), uv.y);

    for (uint index = 0; index < 32; ++index) {
        float id = float(index) + 1.0;
        float2 seed = hash21(id);
        float speed = mix(0.025, 0.11, hash11(id + 8.0));
        float2 direction = normalize(hash21(id + 17.0) - 0.5);
        float2 particle = fract(seed + direction * u.time * speed);
        particle = (particle - 0.5) * float2(aspect, 1.0);

        float mouseDistance = length(particle - mouse);
        particle += normalize(particle - mouse + 0.0001) *
                    exp(-mouseDistance * 8.0) * 0.11;

        float distanceToParticle = length(p - particle);
        float glow = 0.0018 / max(distanceToParticle * distanceToParticle, 0.0005);
        glow *= 0.5 + 0.5 * sin(u.time * 1.7 + id * 2.2);
        color += palette(id * 0.073 + u.time * 0.025) * glow * 0.025;
    }

    float mouseGlow = exp(-length(p - mouse) * 7.0);
    color += float3(0.1, 0.42, 0.9) * mouseGlow * 0.32;
    return color;
}

static float3 waterScene(float2 uv, constant WallpaperUniforms &u) {
    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float2 mouse = (u.mouse - 0.5) * float2(aspect, 1.0);
    float distanceFromMouse = length(p - mouse);

    float ripple = sin(distanceFromMouse * 54.0 - u.time * 7.5)
                 * exp(-distanceFromMouse * 3.5);
    ripple += sin(length(p + float2(0.42, 0.17)) * 31.0 - u.time * 3.1) * 0.22;
    ripple += sin((p.x * 1.7 + p.y) * 12.0 + u.time * 1.8) * 0.12;

    float2 distortion = float2(
        sin((p.y + ripple * 0.035) * 18.0 + u.time),
        cos((p.x - ripple * 0.035) * 16.0 - u.time * 0.8)
    ) * 0.014;

    float caustic = pow(max(0.0, sin((uv.x + distortion.x) * 34.0 + ripple * 2.5)
                                * cos((uv.y + distortion.y) * 28.0 - ripple * 2.0)), 3.0);
    float depth = smoothstep(-0.2, 1.1, uv.y + ripple * 0.045);
    float3 deep = float3(0.005, 0.055, 0.12);
    float3 surface = float3(0.02, 0.38, 0.52);
    float3 color = mix(deep, surface, depth);
    color += float3(0.2, 0.8, 0.9) * caustic * 0.38;
    color += float3(0.12, 0.65, 1.0) * ripple * 0.13;
    return color;
}

static float3 interactiveScene(float2 uv, constant WallpaperUniforms &u) {
    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float2 mouse = (u.mouse - 0.5) * float2(aspect, 1.0);
    float2 delta = p - mouse;
    float radius = length(delta);
    float angle = atan2(delta.y, delta.x);

    float spiral = sin(angle * 7.0 - radius * 24.0 + u.time * 3.0);
    float rings = sin(radius * 48.0 - u.time * 5.0) * exp(-radius * 3.8);
    float field = spiral * exp(-radius * 2.4) + rings;
    float grid = sin((p.x + field * 0.018) * 22.0 + u.time)
               * sin((p.y - field * 0.018) * 22.0 - u.time * 0.7);

    float3 base = mix(float3(0.018, 0.008, 0.07),
                      float3(0.03, 0.08, 0.17), uv.y);
    float3 energy = palette(field * 0.18 + radius * 0.45 + u.time * 0.035);
    float core = exp(-radius * 9.0);
    return base + energy * (field * 0.18 + grid * 0.07 + core * 0.85);
}

fragment float4 wallpaperFragment(
    WallpaperVertexOut input [[stage_in]],
    constant WallpaperUniforms &uniforms [[buffer(0)]]) {
    float2 uv = float2(input.uv.x, 1.0 - input.uv.y);
    float3 color;

    switch (uniforms.effect) {
        case 0:
            color = particleScene(uv, uniforms);
            break;
        case 1:
            color = waterScene(uv, uniforms);
            break;
        default:
            color = interactiveScene(uv, uniforms);
            break;
    }

    color = pow(max(color, 0.0), float3(0.92));
    return float4(color, 1.0);
}
