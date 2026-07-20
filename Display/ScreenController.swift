import AppKit
import Combine

/// Owns macOS screen-change observation and adapts the legacy display scan.
@MainActor
final class ScreenController: ObservableObject {
    @Published private(set) var screens: [DisplayObjc] = []

    private let legacyEngine: WallpaperEngine
    private var screenChangeCancellable: AnyCancellable?

    init(legacyEngine: WallpaperEngine = sharedEngine ?? WallpaperEngine.shared()) {
        self.legacyEngine = legacyEngine
        refresh()
        screenChangeCancellable = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    func refresh() {
        legacyEngine.scanDisplays()
        screens = legacyEngine.getDisplays() as? [DisplayObjc] ?? []
    }
}
