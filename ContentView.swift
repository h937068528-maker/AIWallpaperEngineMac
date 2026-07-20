/*
 * This file is part of LiveWallpaper – LiveWallpaper App for macOS.
 * Copyright (C) 2025 Bios thusvill
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import AVFoundation
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Compatibility Bridge
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

extension View {
    @ViewBuilder
    func compatibleGlass(
        material: NSVisualEffectView.Material = .headerView, cornerRadius: CGFloat = 16
    ) -> some View {
        if #available(macOS 20.0, *) {
            self.background(
                VisualEffectView(material: material)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            )
        } else {
            self.background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - String Localization Extension
extension String {
    var localized: String {
        LanguageManager.shared.localizedString(self)
    }
}

// MARK: - Language Manager
class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: UserDefaultsKeys.appLanguage)
            if currentLanguage == "auto" {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([currentLanguage], forKey: "AppleLanguages")
            }
            UserDefaults.standard.synchronize()
        }
    }

    var availableLanguages: [(code: String, name: String)] {
        [
            ("auto", "system_language".localized),
            ("zh-Hans", "简体中文"),
            ("en", "English"),
        ]
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: UserDefaultsKeys.appLanguage) ?? "auto"
        self.currentLanguage = saved
    }

    func localizedString(_ key: String) -> String {
        let language =
            currentLanguage == "auto"
            ? Bundle.main.preferredLocalizations.first ?? "en"
            : currentLanguage
        guard
            let path = Bundle.main.path(forResource: language, ofType: "lproj")
                ?? Bundle.main.path(
                    forResource: language.components(separatedBy: "-").first, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return NSLocalizedString(key, comment: "")
        }
        return NSLocalizedString(key, tableName: nil, bundle: bundle, comment: "")
    }
}

// MARK: - Localization
enum L {
    private static func text(_ key: String) -> String {
        LanguageManager.shared.localizedString(key)
    }

    static var selectWallpaperFolder: String { text("select_wallpaper_folder") }
    static var generating: String { text("generating") }
    static var reload: String { text("reload") }
    static var settings: String { text("settings") }
    static var wallpaperFolder: String { text("wallpaper_folder") }
    static var selectFolder: String { text("select_folder") }
    static var showInFinder: String { text("show_in_finder") }
    static var videoScalingMode: String { text("video_scaling_mode") }
    static var scaleFill: String { text("scale_fill") }
    static var scaleFit: String { text("scale_fit") }
    static var scaleStretch: String { text("scale_stretch") }
    static var scaleCenter: String { text("scale_center") }
    static var scaleHeightFill: String { text("scale_height_fill") }
    static var appLanguage: String { text("app_language") }
    static var systemLanguage: String { text("system_language") }
    static var languageChangedTitle: String { text("language_changed_title") }
    static var languageChangedMessage: String { text("language_changed_message") }
    static var ok: String { text("ok") }
    static var randomOnStartup: String { text("random_on_startup") }
    static var randomOnLid: String { text("random_on_lid") }
    static var pauseWhenActive: String { text("pause_when_active") }
    static var vignetteBar: String { text("vignette_bar") }
    static var wallpaperRotation: String { text("wallpaper_rotation") }
    static var rotationDelay: String { text("wallpaper_rotation_delay") }
    static var rotationType: String { text("wallpaper_rotation_type") }
    static var rotationSequential: String { text("rotation_sequential") }
    static var rotationRandom: String { text("rotation_random") }
    static var timeHoursMinutes: String { text("time_hours_minutes") }
    static var timeMinutes: String { text("time_minutes") }
    static var videoVolume: String { text("video_volume") }
    static var optimizeCodecs: String { text("optimize_codecs") }
    static var optimize: String { text("optimize") }
    static var clearCache: String { text("clear_cache") }
    static var resetUserData: String { text("reset_user_data") }
    static var reset: String { text("reset") }
    static var selectFolderTitle: String { text("select_folder_title") }
    static var choose: String { text("choose") }
    static var selectFolderOrType: String { text("select_folder_or_type") }
    static var showWindow: String { text("show_window") }
    static var hideWindow: String { text("hide_window") }
    static var quit: String { text("quit") }
}

// MARK: - UserDefaults Keys
enum UserDefaultsKeys {
    static let wallpaperFolder = "WallpaperFolder"
    static let scaleMode = "scale_mode"
    static let randomOnStartup = "random"
    static let randomOnLid = "random_lid"
    static let pauseOnAppFocus = "pauseOnAppFocus"
    static let volumePercentage = "wallpapervolumeprecentage"
    static let launchAtLogin = "LaunchAtLogin"
    static let appLanguage = "app_language"
    static let vignetteBar = "vinttage_bar"
    static let rotation = "rotation"
    static let rdelay = "rdelay"
    static let rtype = "rtype"

}

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var viewModel = WallpaperViewModel()
    @State private var showSettings = false
    @StateObject private var displayManager = DisplayManager()

    @Environment(\.dismiss) private var dismiss
    static var didCloseOnLaunch = false

    var body: some View {

        ZStack {

            VStack(spacing: 0) {
                Spacer(minLength: 20)
                ToolbarView(showSettings: $showSettings, onReload: { viewModel.reloadContent() })
                    .padding(.horizontal).padding(.top, 24).padding(.bottom, 12)

                ZStack(alignment: .bottom) {
                    VideoGridView(
                        videos: viewModel.videos, viewModel: viewModel,
                        onVideoSelect: { video in
                            viewModel.startWallpaper(
                                video: video, displays: Array(displayManager.selectedDisplays))
                        }
                    )
                    .padding(.horizontal, 24).padding(.bottom, 24)

                    DisplayDockView(
                        displays: displayManager.displays,
                        selectedDisplays: $displayManager.selectedDisplays
                    )
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            .ignoresSafeArea(.all)
            .compatibleGlass(cornerRadius: 16)
            .frame(minWidth: 600, minHeight: 250)
            //.sheet(isPresented: $showSettings) { SettingsView(viewModel: viewModel) }
            .onAppear {
                viewModel.loadDisplays()
                viewModel.reloadContent()
                if !Self.didCloseOnLaunch, !AIWallpaperEngine.shared.isFirstLaunch() {
                    Self.didCloseOnLaunch = true
                    dismiss()
                }
            }

            if showSettings {

                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showSettings = false

                    }

                SettingsView(viewModel: viewModel)
                    .shadow(radius: 3)
                    .cornerRadius(15)
                    .onTapGesture {}
                    .animation(.easeInOut, value: showSettings)
            }

        }.animation(.easeInOut, value: showSettings)
    }
}

// MARK: - Toolbar View
struct ToolbarView: View {
    @Binding var showSettings: Bool
    let onReload: () -> Void

    var body: some View {
        HStack {
            Spacer()

            if #available(macOS 26.0, *) {
                Button(action: onReload) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16))
                }
                .buttonStyle(.glass)
                .help(L.reload)
                .accessibilityLabel(L.reload)
            } else {
                Button(action: onReload) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16))
                }
                .help(L.reload)
                .accessibilityLabel(L.reload)
            }

            if #available(macOS 26.0, *) {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gear")
                        .font(.system(size: 16))
                }
                .buttonStyle(.glass)
                .help(L.settings)
                .accessibilityLabel(L.settings)
            } else {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gear")
                        .font(.system(size: 16))
                }
                .help(L.settings)
                .accessibilityLabel(L.settings)
            }
        }
    }
}

// MARK: - Video Grid View
struct VideoGridView: View {
    let videos: [VideoItem]
    let viewModel: WallpaperViewModel
    let onVideoSelect: (VideoItem) -> Void

    private let columns = [GridItem(.adaptive(minimum: THUMBNAIL_WIDTH, maximum: THUMBNAIL_WIDTH), spacing: 6)]

    var body: some View {
        ScrollView {
            if videos.isEmpty {
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.title = L.selectFolderTitle
                    panel.prompt = L.choose

                    if panel.runModal() == .OK, let url = panel.url {
                        viewModel.folderPath = url.path
                        AIWallpaperEngine.shared.selectFolder(url.path)
                        viewModel.reloadContent()
                    }
                } label: {
                    Text(L.selectWallpaperFolder)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(videos) { video in
                        VideoThumbnailButton(video: video) {
                            onVideoSelect(video)
                        }
                        .id(video.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
    }
}

// MARK: - Video Thumbnail Button
struct VideoThumbnailButton: View {
    let video: VideoItem
    let action: () -> Void
    @ObservedObject private var cache = ThumbnailCache.shared

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                let _ = cache.lastUpdate

                if let thumbnail = video.loadThumbnail() {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .frame(height: THUMBNAIL_HEIGHT)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: THUMBNAIL_HEIGHT)
                        .overlay {
                            VStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text(L.generating)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                }

                if let quality = video.quality, !quality.isEmpty {
                    QualityBadge(text: quality)
                        .padding(8)
                }
            }
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .padding(2)
        .help(video.filename)
    }
}

// MARK: - Quality Badge
struct QualityBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.black, lineWidth: 1)
            )
    }
}

// MARK: - Display Manager
class LegacyDisplayManager: ObservableObject {
    @Published var displays: [DisplayObjc] = []
    @Published var selectedDisplays: Set<UInt32> = []

    init() {
        sharedEngine?.scanDisplays()
        updateDisplays()
        CGDisplayRegisterReconfigurationCallback(
            legacyDisplayReconfigCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(
            legacyDisplayReconfigCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    func updateDisplays() {
        sharedEngine?.scanDisplays()
        DispatchQueue.main.async { [weak self] in
            self?.displays = sharedEngine?.getDisplays() as? [DisplayObjc] ?? []
        }
    }
}

nonisolated(unsafe) private let legacyDisplayReconfigCallback: CGDisplayReconfigurationCallBack = {
    display, flags, userInfo in
    guard let userInfo = userInfo else { return }
    let manager = Unmanaged<LegacyDisplayManager>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.async {
        manager.updateDisplays()
        manager.selectedDisplays.removeAll()
    }
}

// MARK: - Display Dock View
struct DisplayDockView: View {
    let displays: [DisplayObjc]
    @Binding var selectedDisplays: Set<UInt32>
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 10) {
            ForEach(displays, id: \.screen) { display in
                DisplayButton(
                    display: display,
                    isSelected: selectedDisplays.contains(display.screen)
                ) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        if selectedDisplays.contains(display.screen) {
                            selectedDisplays.remove(display.screen)
                        } else {
                            selectedDisplays.insert(display.screen)
                        }
                    }
                }
                .matchedGeometryEffect(id: display.screen, in: namespace)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: displays.map { $0.screen })
    }
}

// MARK: - Display Button
struct DisplayButton: View {
    let display: DisplayObjc
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Spacer()
                Text(display.getDisplayName()).font(.system(size: 12, weight: .bold)).lineLimit(1)
                Text(display.getResolution()).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(width: 200, height: 80)
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
            .background {
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(
                        .regular.interactive(), in: .rect(cornerRadius: isSelected ? 26 : 20))
                } else {
                    VisualEffectView(material: isSelected ? .selection : .headerView)
                        .clipShape(RoundedRectangle(cornerRadius: isSelected ? 26 : 20))
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(
                        Color.yellow, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .shadow(
            color: isSelected ? Color.yellow.opacity(0.45) : Color.black.opacity(0.15),
            radius: isSelected ? 20 : 10, y: 8
        )
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: isSelected)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showFolderPicker = false
    @AppStorage(UserDefaultsKeys.scaleMode) var scaleMode: Int = 0
    @State private var localMinutes: Int = 60
    @State private var isShowingView = true
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header
            HStack {
                Text(L.settings)
                    .font(.title2)
                    .fontWeight(.bold)

            }
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Folder Selection
                    SettingRow(title: L.wallpaperFolder) {
                        HStack {
                            TextField(L.selectFolderOrType, text: $viewModel.folderPath)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                            Button(action: selectFolder) {
                                //Image(systemName: "folder.fill")
                                Image("openfolder").resizable().frame(width: 23, height: 23)
                            }
                            .help(L.selectFolder)
                            .accessibilityLabel(L.selectFolder)
                            Button(action: openInFinder) {
                                Image("folder").resizable().frame(width: 23, height: 23)
                            }
                            .help(L.showInFinder)
                            .accessibilityLabel(L.showInFinder)
                            
                            
                        }
                    }

                    Divider()

                    // Scale Mode
                    SettingRow(title: L.videoScalingMode) {

                        Picker("", selection: $scaleMode) {
                            Text(L.scaleFill).tag(0)
                            Text(L.scaleFit).tag(1)
                            Text(L.scaleStretch).tag(2)
                            Text(L.scaleCenter).tag(3)
                            Text(L.scaleHeightFill).tag(4)
                        }
                        .onChange(of: scaleMode) {

                            viewModel.engine.updateScaleMode(scaleMode)
                        }

                    }

                    Divider()

                    // Language Selection
                    SettingRow(title: L.appLanguage) {
                        Picker(
                            "",
                            selection: Binding(
                                get: { languageManager.currentLanguage },
                                set: { newValue in
                                    languageManager.currentLanguage = newValue
                                    let alert = NSAlert()
                                    alert.messageText = L.languageChangedTitle
                                    alert.informativeText = L.languageChangedMessage
                                    alert.alertStyle = .informational
                                    alert.addButton(withTitle: L.ok)
                                    alert.runModal()
                                }
                            )
                        ) {
                            Text(L.systemLanguage).tag("auto")
                            Text("简体中文").tag("zh-Hans")
                            Text("English").tag("en")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }

                    Divider()

                    // Random Wallpaper on Startup
                    SettingRow(title: L.randomOnStartup) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: {
                                    UserDefaults.standard.bool(
                                        forKey: UserDefaultsKeys.randomOnStartup)
                                },
                                set: {
                                    UserDefaults.standard.set(
                                        $0, forKey: UserDefaultsKeys.randomOnStartup)
                                }
                            )
                        )
                        .toggleStyle(.switch)
                    }

                    // Random Wallpaper on Wakeup
                    SettingRow(title: L.randomOnLid) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: {
                                    UserDefaults.standard.bool(forKey: UserDefaultsKeys.randomOnLid)
                                },
                                set: {
                                    UserDefaults.standard.set(
                                        $0, forKey: UserDefaultsKeys.randomOnLid)
                                }
                            )
                        )
                        .toggleStyle(.switch)
                    }

                    // Auto-Pause When App is Active
                    SettingRow(title: L.pauseWhenActive) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: {
                                    UserDefaults.standard.bool(
                                        forKey: UserDefaultsKeys.pauseOnAppFocus)
                                },
                                set: {
                                    UserDefaults.standard.set(
                                        $0, forKey: UserDefaultsKeys.pauseOnAppFocus)
                                }
                            )
                        )
                        .toggleStyle(.switch)
                    }

                    //Vinttage Bar
                    SettingRow(title: L.vignetteBar) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: {
                                    UserDefaults.standard.bool(forKey: UserDefaultsKeys.vignetteBar)
                                },
                                set: {
                                    UserDefaults.standard.set(
                                        $0, forKey: UserDefaultsKeys.vignetteBar)
                                }
                            )
                        )
                        .toggleStyle(.switch)
                    }

                    Divider()

                    SettingRow(title: L.wallpaperRotation) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: {
                                    UserDefaults.standard.bool(forKey: UserDefaultsKeys.rotation)
                                },
                                set: { newValue in
                                    let engine = viewModel.engine

                                    engine.isRotationRunning = newValue
                                    if newValue {

                                        engine.startWallpaperRotation()

                                    } else {
                                        engine.stopWallpaperRotation()
                                    }
                                    UserDefaults.standard.set(
                                        newValue, forKey: UserDefaultsKeys.rotation)
                                }
                            )
                        ).toggleStyle(.switch)

                    }

                    SettingRow(title: L.rotationDelay) {
                        HStack(spacing: 8) {
                            // 1. The Typeable Field
                            TextField("", value: $localMinutes, format: .number)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 40)  // Keeps it compact
                                .onSubmit {
                                    // Ensure the typed value stays within your bounds
                                    localMinutes = min(max(localMinutes, 1), 1440)
                                }

                            // 2. The Stepper (with an empty label)
                            Stepper("", value: $localMinutes, in: 1...1440, step: 4)
                                .labelsHidden()  // This hides the extra space Stepper usually takes
                                .onChange(of: localMinutes) { newValue in
                                    viewModel.engine.rotationDelay = Int32(newValue * 60)
                                    UserDefaults.standard.set(
                                        (newValue * 60), forKey: UserDefaultsKeys.rdelay)
                                    print("Delay updated to: \(viewModel.engine.rotationDelay)")
                                }

                            // 3. The Formatted Unit
                            Text(formatTime(localMinutes))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize()
                        }

                    }

                    .onAppear {
                        localMinutes =
                            UserDefaults.standard.integer(forKey: UserDefaultsKeys.rdelay) / 60
                    }

                    SettingRow(title: L.rotationType) {
                        Picker(
                            "",
                            selection: Binding(
                                get: { viewModel.engine.rotationType },
                                set: { newValue in
                                    viewModel.engine.rotationType = newValue
                                }
                            )
                        ) {
                            Text(L.rotationSequential).tag(RotationType.sequential)
                            Text(L.rotationRandom).tag(RotationType.random)
                        }
                        .onChange(of: viewModel.engine.rotationType) {
                            if viewModel.engine.rotationType == RotationType.sequential {
                                UserDefaults.standard.set(1, forKey: UserDefaultsKeys.rtype)
                            } else {
                                UserDefaults.standard.set(2, forKey: UserDefaultsKeys.rtype)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }

                    Divider()

                    // Video Volume
                    SettingRow(title: L.videoVolume) {
                        HStack {
                            Slider(value: $viewModel.volume, in: 0...100, step: 1)
                                .frame(width: 200)
                                .onChange(of: viewModel.volume) { newValue in
                                    viewModel.engine.updateVolume(newValue)
                                }
                            Text("\(Int(viewModel.volume))%")
                                .frame(width: 60, alignment: .leading)
                                .monospacedDigit()
                        }
                    }

                    Divider()

                    // Optimize Videos
                    SettingRow(title: L.optimizeCodecs) {
                        Button(L.optimize) {
                            viewModel.optimizeVideos()
                        }
                        .disabled(true)
                    }

                    // Clear Cache
                    SettingRow(title: L.clearCache) {
                        Button(L.clearCache) {
                            viewModel.clearCache()
                        }
                    }

                    // Reset User Data
                    SettingRow(title: L.resetUserData) {
                        Button(L.reset) {
                            viewModel.resetUserData()
                        }
                    }
                }
                .padding()
            }
        }
        .padding()
        .frame(width: 600, height: 500)
        .background(.ultraThinMaterial)
        .compatibleGlass(cornerRadius: 1)

    }
    func formatTime(_ totalMinutes: Int) -> String {
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return String(format: L.timeHoursMinutes, h, m)
        }
        return String(format: L.timeMinutes, m)
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = L.selectFolderTitle
        panel.prompt = L.choose

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.folderPath = url.path
            viewModel.engine.selectFolder(url.path)
            viewModel.reloadContent()
        }
    }

    private func openInFinder() {
        if let url = URL(string: "file://\(viewModel.folderPath)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Setting Row
struct SettingRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 200, alignment: .leading)
            content
            Spacer()
        }
    }
}

#Preview {
    ContentView()
}

#Preview {
    SettingsView(viewModel: WallpaperViewModel())
}
