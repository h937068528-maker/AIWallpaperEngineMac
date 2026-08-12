#include <metal_stdlib>
using namespace metal;

struct Particle {
    float2 position;
    float2 velocity;
    float2 target;
    float life;
    float seed;
};

struct SimulationUniforms {
    float2 mousePosition;
    float2 previousMousePosition;
    float2 shockwaveCenter;
    float2 simulationBounds;
    float deltaTime;
    float time;
    float interactionRadius;
    float forceStrength;
    float returnSpeed;
    float swirlStrength;
    float shockwaveAge;
    float shockwaveStrength;
    float pressure;
    float audioLevel;
    float audioBass;
    uint mouseActive;
    uint particleCount;
    uint padding;
};

struct RenderUniforms {
    float2 viewportSize;
    float2 simulationBounds;
    float particleSize;
    float trailLength;
    float time;
    float audioLevel;
};

struct ParticleVertexOut {
    float4 position [[position]];
    float2 localCoordinate;
    float intensity;
    float hue;
};

kernel void updateParticles(
    device const Particle *source [[buffer(0)]],
    device Particle *destination [[buffer(1)]],
    constant SimulationUniforms &uniforms [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
    if (id >= uniforms.particleCount) {
        return;
    }

    Particle particle = source[id];
    float dt = uniforms.deltaTime;
    float2 force = (particle.target - particle.position) * uniforms.returnSpeed;
    force += normalize(particle.position + float2(0.0001)) * uniforms.audioBass * sin(uniforms.time * 8.0 + particle.seed * 20.0) * 0.45;

    if (uniforms.mouseActive != 0) {
        float2 mouseDelta = uniforms.mousePosition - particle.position;
        float distanceToMouse = max(length(mouseDelta), 0.0001);
        float falloff = smoothstep(uniforms.interactionRadius, 0.0, distanceToMouse);
        float2 radial = mouseDelta / distanceToMouse;
        force += radial * uniforms.forceStrength * falloff * uniforms.pressure;

        float2 tangent = float2(-radial.y, radial.x);
        float pointerSpeed = length(uniforms.mousePosition - uniforms.previousMousePosition) / max(dt, 0.001);
        force += tangent * uniforms.swirlStrength * falloff * min(pointerSpeed * 0.04 + 0.4, 2.5);
    }

    if (uniforms.shockwaveAge >= 0.0 && uniforms.shockwaveAge < 1.4) {
        float2 shockDelta = particle.position - uniforms.shockwaveCenter;
        float shockDistance = max(length(shockDelta), 0.0001);
        float ringRadius = uniforms.shockwaveAge * 1.65;
        float ring = exp(-pow((shockDistance - ringRadius) * 18.0, 2.0));
        float decay = exp(-uniforms.shockwaveAge * 1.8);
        force += (shockDelta / shockDistance) * ring * decay * uniforms.shockwaveStrength;
    }

    particle.velocity += force * dt;
    particle.velocity *= pow(0.24, dt);
    particle.position += particle.velocity * dt;
    particle.life -= dt;

    float2 limits = uniforms.simulationBounds * 1.12;
    if (abs(particle.position.x) > limits.x) {
        particle.position.x = clamp(particle.position.x, -limits.x, limits.x);
        particle.velocity.x *= -0.45;
    }
    if (abs(particle.position.y) > limits.y) {
        particle.position.y = clamp(particle.position.y, -limits.y, limits.y);
        particle.velocity.y *= -0.45;
    }
    if (particle.life <= 0.0) {
        particle.life = 4.0 + fract(sin(particle.seed * 913.7) * 43758.5453) * 7.0;
        particle.velocity *= 0.35;
    }
    destination[id] = particle;
}

vertex ParticleVertexOut particleVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    device const Particle *particles [[buffer(0)]],
    constant RenderUniforms &uniforms [[buffer(1)]]) {
    const float2 corners[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };

    Particle particle = particles[instanceID];
    float2 velocity = particle.velocity;
    float speed = length(velocity);
    float2 direction = speed > 0.0001 ? velocity / speed : float2(1.0, 0.0);
    float2 perpendicular = float2(-direction.y, direction.x);
    float tailPixels = min(speed * uniforms.trailLength * 80.0, 42.0);
    float2 corner = corners[vertexID];
    float2 pixelOffset = perpendicular * corner.y * uniforms.particleSize
        + direction * (corner.x * uniforms.particleSize - max(-corner.x, 0.0) * tailPixels);
    float2 ndcOffset = pixelOffset * 2.0 / max(uniforms.viewportSize, float2(1.0));
    float2 center = float2(
        particle.position.x / max(uniforms.simulationBounds.x, 0.001),
        particle.position.y
    );

    ParticleVertexOut output;
    output.position = float4(center + ndcOffset, 0.0, 1.0);
    output.localCoordinate = corner;
    output.intensity = 0.62 + min(speed * 0.8, 0.38) + uniforms.audioLevel * 0.5;
    output.hue = particle.seed;
    return output;
}

fragment float4 particleFragment(ParticleVertexOut input [[stage_in]]) {
    float distanceFromCenter = length(input.localCoordinate);
    float core = smoothstep(1.0, 0.0, distanceFromCenter);
    float glow = exp(-distanceFromCenter * distanceFromCenter * 3.8);
    float3 cyan = mix(float3(0.05, 0.58, 1.0), float3(0.25, 1.0, 0.92), input.hue);
    float alpha = (core * 0.7 + glow * 0.35) * input.intensity;
    return float4(cyan * (1.2 + glow * 1.8), alpha);
}
