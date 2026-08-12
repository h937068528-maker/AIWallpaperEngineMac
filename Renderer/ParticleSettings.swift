import Combine
import Foundation

enum ParticleQualityPreset: String, CaseIterable, Identifiable, Sendable {
    case powerSaver
    case balanced
    case highQuality

    var id: String { rawValue }

    var particleCount: Int {
        switch self {
        case .powerSaver: 30_000
        case .balanced: 100_000
        case .highQuality: 250_000
        }
    }

    var targetFPS: Int {
        switch self {
        case .powerSaver: 30
        case .balanced, .highQuality: 60
        }
    }
}

struct ParticleSettingsSnapshot: Sendable {
    var particleCount: Int
    var particleSize: Float
    var interactionRadius: Float
    var forceStrength: Float
    var returnSpeed: Float
    var trailLength: Float
    var targetFPS: Int

    static let balanced = ParticleSettingsSnapshot(
        particleCount: ParticleQualityPreset.balanced.particleCount,
        particleSize: 2.6,
        interactionRadius: 0.28,
        forceStrength: -2.2,
        returnSpeed: 0.85,
        trailLength: 0.45,
        targetFPS: ParticleQualityPreset.balanced.targetFPS
    )
}

extension Notification.Name {
    static let particleSettingsDidChange = Notification.Name(
        "com.aiwallpaperengine.mac.particleSettingsDidChange"
    )
}

@MainActor
final class ParticleSettingsStore: ObservableObject {
    static let shared = ParticleSettingsStore()

    @Published var particleCount: Int { didSet { persist() } }
    @Published var particleSize: Double { didSet { persist() } }
    @Published var interactionRadius: Double { didSet { persist() } }
    @Published var forceStrength: Double { didSet { persist() } }
    @Published var returnSpeed: Double { didSet { persist() } }
    @Published var trailLength: Double { didSet { persist() } }
    @Published var targetFPS: Int { didSet { persist() } }
    @Published var selectedPreset: ParticleQualityPreset? { didSet { persist() } }

    private enum Key {
        static let count = "particle.count"
        static let size = "particle.size"
        static let radius = "particle.interactionRadius"
        static let force = "particle.forceStrength"
        static let returnSpeed = "particle.returnSpeed"
        static let trail = "particle.trailLength"
        static let fps = "particle.targetFPS"
        static let preset = "particle.qualityPreset"
    }

    private let defaults: UserDefaults
    private var isLoading = true

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let fallback = ParticleSettingsSnapshot.balanced
        particleCount = defaults.object(forKey: Key.count) as? Int ?? fallback.particleCount
        particleSize = defaults.object(forKey: Key.size) as? Double ?? Double(fallback.particleSize)
        interactionRadius = defaults.object(forKey: Key.radius) as? Double
            ?? Double(fallback.interactionRadius)
        forceStrength = defaults.object(forKey: Key.force) as? Double
            ?? Double(fallback.forceStrength)
        returnSpeed = defaults.object(forKey: Key.returnSpeed) as? Double
            ?? Double(fallback.returnSpeed)
        trailLength = defaults.object(forKey: Key.trail) as? Double
            ?? Double(fallback.trailLength)
        targetFPS = defaults.object(forKey: Key.fps) as? Int ?? fallback.targetFPS
        selectedPreset = defaults.string(forKey: Key.preset).flatMap(ParticleQualityPreset.init)
            ?? .balanced
        isLoading = false
    }

    var snapshot: ParticleSettingsSnapshot {
        ParticleSettingsSnapshot(
            particleCount: min(max(particleCount, 10_000), 250_000),
            particleSize: Float(min(max(particleSize, 1), 8)),
            interactionRadius: Float(min(max(interactionRadius, 0.08), 0.8)),
            forceStrength: Float(min(max(forceStrength, -6), 6)),
            returnSpeed: Float(min(max(returnSpeed, 0.05), 3)),
            trailLength: Float(min(max(trailLength, 0), 2)),
            targetFPS: min(max(targetFPS, 15), 120)
        )
    }

    func apply(_ preset: ParticleQualityPreset) {
        isLoading = true
        selectedPreset = preset
        particleCount = preset.particleCount
        targetFPS = preset.targetFPS
        switch preset {
        case .powerSaver:
            particleSize = 2.2
            trailLength = 0.2
        case .balanced:
            particleSize = 2.6
            trailLength = 0.45
        case .highQuality:
            particleSize = 2.9
            trailLength = 0.7
        }
        isLoading = false
        persist()
    }

    func markCustom() {
        guard selectedPreset != nil else { return }
        selectedPreset = nil
    }

    private func persist() {
        guard !isLoading else { return }
        defaults.set(particleCount, forKey: Key.count)
        defaults.set(particleSize, forKey: Key.size)
        defaults.set(interactionRadius, forKey: Key.radius)
        defaults.set(forceStrength, forKey: Key.force)
        defaults.set(returnSpeed, forKey: Key.returnSpeed)
        defaults.set(trailLength, forKey: Key.trail)
        defaults.set(targetFPS, forKey: Key.fps)
        if let selectedPreset {
            defaults.set(selectedPreset.rawValue, forKey: Key.preset)
        } else {
            defaults.removeObject(forKey: Key.preset)
        }
        NotificationCenter.default.post(name: .particleSettingsDidChange, object: nil)
    }
}
