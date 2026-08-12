import Accelerate
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Local-file music playback and FFT analysis for wallpaper effects.
/// Audio is user-selected only; no microphone or system-audio capture is used.
final class MusicEffectEngine: NSObject, @unchecked Sendable {
    static let shared = MusicEffectEngine()

    struct Frame: Sendable {
        let level: Float
        let bass: Float
        static let silent = Frame(level: 0, bass: 0)
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let lock = NSLock()
    private let fftSize = 1024
    private var fftSetup: vDSP_DFT_Setup?
    private var window: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var realOut: [Float]
    private var imaginaryOut: [Float]
    private var magnitudes: [Float]
    private var frame = Frame.silent
    private var selectedFile: AVAudioFile?
    private let captureQueue = DispatchQueue(label: "com.aiwallpaperengine.music.systemAudio")
    private var systemStream: SCStream?

    private override init() {
        window = [Float](repeating: 0, count: fftSize)
        real = [Float](repeating: 0, count: fftSize)
        imaginary = [Float](repeating: 0, count: fftSize)
        realOut = [Float](repeating: 0, count: fftSize)
        imaginaryOut = [Float](repeating: 0, count: fftSize)
        magnitudes = [Float](repeating: 0, count: fftSize / 2)
        super.init()
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        player.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: nil) { [weak self] buffer, _ in
            guard let channel = buffer.floatChannelData?.pointee else { return }
            let count = min(Int(buffer.frameLength), 1024)
            let samples = Array(UnsafeBufferPointer(start: channel, count: count))
            Task { @MainActor [weak self] in self?.analyze(samples: samples) }
        }
    }

    func play(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        selectedFile = file
        if !engine.isRunning { try engine.start() }
        scheduleLoop(file)
        if !player.isPlaying { player.play() }
    }

    func stop() {
        player.stop()
        lock.lock(); frame = .silent; lock.unlock()
    }

    /// Enables reactive effects for audio already playing in another app,
    /// such as NetEase Cloud Music. macOS presents Screen Recording consent.
    func startSystemAudio() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first else { return }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.capturesAudio = true
                configuration.excludesCurrentProcessAudio = true
                configuration.sampleRate = 48_000
                configuration.channelCount = 2
                configuration.width = 2
                configuration.height = 2
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: captureQueue)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
                try await stream.startCapture()
                setSystemStream(stream)
            } catch {
                NSLog("System audio effects unavailable: %@", error.localizedDescription)
            }
        }
    }

    func stopSystemAudio() {
        let stream = takeSystemStream()
        Task { try? await stream?.stopCapture() }
    }

    private func setSystemStream(_ stream: SCStream?) {
        lock.lock()
        systemStream = stream
        lock.unlock()
    }

    private func takeSystemStream() -> SCStream? {
        lock.lock()
        defer { lock.unlock() }
        let stream = systemStream
        systemStream = nil
        return stream
    }

    func currentFrame() -> Frame {
        lock.lock(); defer { lock.unlock() }
        return frame
    }

    private func scheduleLoop(_ file: AVAudioFile) {
        player.scheduleFile(file, at: nil) { [weak self] in
            guard let self, self.player.isPlaying else { return }
            self.scheduleLoop(file)
        }
    }

    private func analyze(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?.pointee else { return }
        let count = min(Int(buffer.frameLength), fftSize)
        analyze(samples: channel, count: count)
    }

    private func analyze(samples: [Float]) {
        samples.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return }
            analyze(samples: baseAddress, count: min(pointer.count, fftSize))
        }
    }

    private func analyze(samples: UnsafePointer<Float>, count: Int) {
        guard count > 0, let fftSetup else { return }
        lock.lock()
        real.withUnsafeMutableBufferPointer { destination in
            destination.initialize(repeating: 0)
            destination.baseAddress!.assign(from: samples, count: count)
        }
        vDSP_vmul(real, 1, window, 1, &real, 1, vDSP_Length(fftSize))
        vDSP_vclr(&imaginary, 1, vDSP_Length(fftSize))
        vDSP_DFT_Execute(fftSetup, real, imaginary, &realOut, &imaginaryOut)
        realOut.withUnsafeMutableBufferPointer { realPointer in
            imaginaryOut.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }
        var level: Float = 0
        vDSP_meanv(magnitudes, 1, &level, vDSP_Length(magnitudes.count))
        var bass: Float = 0
        vDSP_meanv(magnitudes, 1, &bass, vDSP_Length(24))
        frame = Frame(
            level: min(sqrt(level) * 18, 1),
            bass: min(sqrt(bass) * 24, 1)
        )
        lock.unlock()
    }
}

extension MusicEffectEngine: SCStreamOutput, SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio, sampleBuffer.isValid else { return }
        let buffers = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(buffers.unsafeMutablePointer) }
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: buffers.unsafeMutablePointer,
            bufferListSize: AudioBufferList.sizeInBytes(maximumBuffers: 2),
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let data = buffers[0].mData else { return }
        let samples = Array(UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: Float.self),
            count: Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size
        ))
        Task { @MainActor [weak self] in self?.analyze(samples: samples) }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("System audio stream stopped: %@", error.localizedDescription)
    }
}
