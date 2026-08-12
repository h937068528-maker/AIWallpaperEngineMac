import Foundation
import Metal

struct SmokeParticle {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var target: SIMD2<Float>
    var life: Float
    var seed: Float
}

struct SmokeSimulationUniforms {
    var mousePosition = SIMD2<Float>(0.2, 0.1)
    var previousMousePosition = SIMD2<Float>(0.18, 0.1)
    var shockwaveCenter = SIMD2<Float>(0, 0)
    var simulationBounds = SIMD2<Float>(16.0 / 9.0, 1)
    var deltaTime: Float = 1.0 / 60.0
    var time: Float = 1
    var interactionRadius: Float = 0.3
    var forceStrength: Float = -2
    var returnSpeed: Float = 0.8
    var swirlStrength: Float = 0.4
    var shockwaveAge: Float = 0.2
    var shockwaveStrength: Float = 3.8
    var pressure: Float = 1
    var mouseActive: UInt32 = 1
    var particleCount: UInt32
    var padding: UInt32 = 0
}

struct SmokeRenderUniforms {
    var viewportSize = SIMD2<Float>(640, 360)
    var simulationBounds = SIMD2<Float>(16.0 / 9.0, 1)
    var particleSize: Float = 2.6
    var trailLength: Float = 0.45
    var time: Float = 1
    var padding: Float = 0
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Particle smoke test failed: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count >= 2 else {
    fail("pass the ParticleShaders.metal path and optional particle count")
}
guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
    fail("Metal device unavailable")
}

do {
    let shader = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    let library = try device.makeLibrary(source: shader, options: nil)
    guard
        let computeFunction = library.makeFunction(name: "updateParticles"),
        let vertexFunction = library.makeFunction(name: "particleVertex"),
        let fragmentFunction = library.makeFunction(name: "particleFragment")
    else { fail("functions missing") }

    let computePipeline = try device.makeComputePipelineState(function: computeFunction)
    let renderDescriptor = MTLRenderPipelineDescriptor()
    renderDescriptor.vertexFunction = vertexFunction
    renderDescriptor.fragmentFunction = fragmentFunction
    renderDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    renderDescriptor.colorAttachments[0].isBlendingEnabled = true
    renderDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
    renderDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
    let renderPipeline = try device.makeRenderPipelineState(descriptor: renderDescriptor)

    let count = CommandLine.arguments.count > 2
        ? min(max(Int(CommandLine.arguments[2]) ?? 1_024, 1), 250_000)
        : 1_024
    let particles = (0..<count).map { index in
        let x = Float(index % 64) / 32 - 1
        let y = Float(index / 64) / 8 - 1
        return SmokeParticle(
            position: SIMD2(x, y),
            velocity: .zero,
            target: SIMD2(x, y),
            life: 5,
            seed: Float(index) / Float(count)
        )
    }
    let particleLength = particles.count * MemoryLayout<SmokeParticle>.stride
    guard let destinationBuffer = device.makeBuffer(length: particleLength, options: .storageModeShared)
    else { fail("particle destination buffer unavailable") }
    let sourceBuffer: MTLBuffer = particles.withUnsafeBytes { bytes in
        guard let baseAddress = bytes.baseAddress,
            let buffer = device.makeBuffer(bytes: baseAddress, length: bytes.count)
        else { fail("particle source buffer unavailable") }
        return buffer
    }

    var simulation = SmokeSimulationUniforms(particleCount: UInt32(count))
    var rendering = SmokeRenderUniforms()
    guard
        let simulationBuffer = device.makeBuffer(
            bytes: &simulation,
            length: MemoryLayout<SmokeSimulationUniforms>.stride
        ),
        let renderBuffer = device.makeBuffer(
            bytes: &rendering,
            length: MemoryLayout<SmokeRenderUniforms>.stride
        )
    else { fail("uniform buffers unavailable") }

    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: 640,
        height: 360,
        mipmapped: false
    )
    textureDescriptor.usage = [.renderTarget]
    guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
        fail("render target unavailable")
    }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

    guard let commandBuffer = queue.makeCommandBuffer(),
        let compute = commandBuffer.makeComputeCommandEncoder()
    else { fail("compute encoder unavailable") }
    compute.setComputePipelineState(computePipeline)
    compute.setBuffer(sourceBuffer, offset: 0, index: 0)
    compute.setBuffer(destinationBuffer, offset: 0, index: 1)
    compute.setBuffer(simulationBuffer, offset: 0, index: 2)
    let width = min(computePipeline.maxTotalThreadsPerThreadgroup, 256)
    compute.dispatchThreads(
        MTLSize(width: count, height: 1, depth: 1),
        threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
    )
    compute.endEncoding()

    guard let render = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
        fail("render encoder unavailable")
    }
    render.setRenderPipelineState(renderPipeline)
    render.setVertexBuffer(destinationBuffer, offset: 0, index: 0)
    render.setVertexBuffer(renderBuffer, offset: 0, index: 1)
    render.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
    render.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    if let error = commandBuffer.error { fail(error.localizedDescription) }

    print(
        "PARTICLE_METAL_SMOKE_OK device=\(device.name) particles=\(count) "
            + "particleStride=\(MemoryLayout<SmokeParticle>.stride) "
            + "simulationStride=\(MemoryLayout<SmokeSimulationUniforms>.stride)"
    )
} catch {
    fail(error.localizedDescription)
}
