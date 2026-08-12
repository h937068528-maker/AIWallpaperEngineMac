import Combine
import CoreGraphics
import Foundation

/// UI-facing display selection model backed by `ScreenController`.
@MainActor
final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [DisplayObjc] = []
    @Published var selectedDisplays: Set<CGDirectDisplayID> = [] {
        didSet {
            guard !isApplyingScreenUpdate else { return }
            if selectedDisplays.isEmpty {
                explicitlySelectedDisplayUUIDs.removeAll()
            } else {
                explicitlySelectedDisplayUUIDs = Set(
                    displays.compactMap { display in
                        selectedDisplays.contains(display.screen)
                            ? display.uuid : nil
                    }
                )
            }
        }
    }

    private let screenController: ScreenController
    private var cancellables = Set<AnyCancellable>()
    private var explicitlySelectedDisplayUUIDs: Set<String> = []
    private var isApplyingScreenUpdate = false

    init(screenController: ScreenController = ScreenController()) {
        self.screenController = screenController
        displays = screenController.screens

        screenController.$screens
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] screens in
                guard let self else { return }
                isApplyingScreenUpdate = true
                defer { isApplyingScreenUpdate = false }
                displays = screens
                if explicitlySelectedDisplayUUIDs.isEmpty {
                    selectedDisplays.removeAll()
                } else {
                    selectedDisplays = Set(
                        screens.compactMap { display in
                            explicitlySelectedDisplayUUIDs
                                .contains(display.uuid)
                                ? display.screen : nil
                        }
                    )
                }
            }
            .store(in: &cancellables)
    }

    func updateDisplays() {
        screenController.refresh()
    }
}
