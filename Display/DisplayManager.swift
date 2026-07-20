import Combine
import CoreGraphics
import Foundation

/// UI-facing display selection model backed by `ScreenController`.
@MainActor
final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [DisplayObjc] = []
    @Published var selectedDisplays: Set<CGDirectDisplayID> = []

    private let screenController: ScreenController
    private var cancellables = Set<AnyCancellable>()

    init(screenController: ScreenController = ScreenController()) {
        self.screenController = screenController
        displays = screenController.screens

        screenController.$screens
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] screens in
                self?.displays = screens
                self?.selectedDisplays.removeAll()
            }
            .store(in: &cancellables)
    }

    func updateDisplays() {
        screenController.refresh()
    }
}
