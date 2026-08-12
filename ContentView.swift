/*
 * This file is part of LiveWallpaper – LiveWallpaper App for macOS.
 * Copyright (C) 2025 Bios thusvill
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// MARK: - AppKit material bridge

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
        nsView.state = .active
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            }
    }
}

// MARK: - Localization

extension String {
    var localized: String { LanguageManager.shared.localizedString(self) }
}

final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: UserDefaultsKeys.appLanguage)
            if currentLanguage == "auto" {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([currentLanguage], forKey: "AppleLanguages")
            }
        }
    }

    private init() {
        currentLanguage = UserDefaults.standard.string(forKey: UserDefaultsKeys.appLanguage) ?? "auto"
    }

    func localizedString(_ key: String) -> String {
        let language = currentLanguage == "auto"
            ? Bundle.main.preferredLocalizations.first ?? "en"
            : currentLanguage
        guard
            let path = Bundle.main.path(forResource: language, ofType: "lproj")
                ?? Bundle.main.path(
                    forResource: language.components(separatedBy: "-").first,
                    ofType: "lproj"
                ),
            let bundle = Bundle(path: path)
        else {
            return NSLocalizedString(key, comment: "")
        }
        return NSLocalizedString(key, tableName: nil, bundle: bundle, comment: "")
    }
}

enum L {
    private static func text(_ key: String) -> String {
        LanguageManager.shared.localizedString(key)
    }

    static var appName: String { text("app_name") }
    static var library: String { text("library") }
    static var librarySubtitle: String { text("library_subtitle") }
    static var effects: String { text("effects") }
    static var marketplace: String { text("marketplace") }
    static var aiWallpaper: String { text("ai_wallpaper") }
    static var aiWallpaperSubtitle: String { text("ai_wallpaper_subtitle") }
    static var aiDemoMode: String { text("ai_demo_mode") }
    static var aiDemoModeDescription: String { text("ai_demo_mode_description") }
    static var aiOpenAIMode: String { text("ai_openai_mode") }
    static var aiOpenAIModeDescription: String { text("ai_openai_mode_description") }
    static var aiDescribeWallpaper: String { text("ai_describe_wallpaper") }
    static var aiPromptPlaceholder: String { text("ai_prompt_placeholder") }
    static var aiStyle: String { text("ai_style") }
    static var aiStyleCinematic: String { text("ai_style_cinematic") }
    static var aiStyleIllustration: String { text("ai_style_illustration") }
    static var aiStyleMinimal: String { text("ai_style_minimal") }
    static var aiStyleAbstract: String { text("ai_style_abstract") }
    static var aiGenerate: String { text("ai_generate") }
    static var aiGenerating: String { text("ai_generating") }
    static var aiGenerationHistory: String { text("ai_generation_history") }
    static var aiNoHistory: String { text("ai_no_history") }
    static var aiNoHistoryDescription: String { text("ai_no_history_description") }
    static var aiEmptyPrompt: String { text("ai_empty_prompt") }
    static var aiInvalidFolder: String { text("ai_invalid_folder") }
    static var aiGenerationFailed: String { text("ai_generation_failed") }
    static var aiProvider: String { text("ai_provider") }
    static var aiOpenAIConnection: String { text("ai_openai_connection") }
    static var aiKeyConfigured: String { text("ai_key_configured") }
    static var aiKeyNotConfigured: String { text("ai_key_not_configured") }
    static var aiConfigureKey: String { text("ai_configure_key") }
    static var aiReplaceKey: String { text("ai_replace_key") }
    static var aiRemoveKey: String { text("ai_remove_key") }
    static var aiRemoveKeyTitle: String { text("ai_remove_key_title") }
    static var aiRemoveKeyDescription: String { text("ai_remove_key_description") }
    static var aiKeySecurityDescription: String { text("ai_key_security_description") }
    static var aiAPIKeyPlaceholder: String { text("ai_api_key_placeholder") }
    static var aiShowKey: String { text("ai_show_key") }
    static var aiAPIUsageNotice: String { text("ai_api_usage_notice") }
    static var aiValidateAndSave: String { text("ai_validate_and_save") }
    static var aiValidatingKey: String { text("ai_validating_key") }
    static var aiCancelGeneration: String { text("ai_cancel_generation") }
    static var aiVolcengineName: String { text("ai_volcengine_name") }
    static var aiVolcengineConnection: String { text("ai_volcengine_connection") }
    static var aiVolcengineMode: String { text("ai_volcengine_mode") }
    static var aiVolcengineModeDescription: String {
        text("ai_volcengine_mode_description")
    }
    static var aiVolcengineConfigure: String { text("ai_volcengine_configure") }
    static var aiVolcengineSecurityDescription: String {
        text("ai_volcengine_security_description")
    }
    static var aiVolcengineKeyPlaceholder: String {
        text("ai_volcengine_key_placeholder")
    }
    static var aiVolcengineModelID: String { text("ai_volcengine_model_id") }
    static var aiVolcengineModelHint: String { text("ai_volcengine_model_hint") }
    static var aiVolcengineUsageNotice: String {
        text("ai_volcengine_usage_notice")
    }
    static var aiVolcengineSave: String { text("ai_volcengine_save") }
    static var aiVolcengineRemoveKeyTitle: String {
        text("ai_volcengine_remove_key_title")
    }
    static var aiVolcengineRemoveKeyDescription: String {
        text("ai_volcengine_remove_key_description")
    }
    static var aiVolcengineInvalidKey: String {
        text("ai_volcengine_invalid_key")
    }
    static var aiVolcengineInvalidModel: String {
        text("ai_volcengine_invalid_model")
    }
    static var aiVolcengineMissingKey: String {
        text("ai_volcengine_missing_key")
    }
    static var aiVolcengineInvalidResponse: String {
        text("ai_volcengine_invalid_response")
    }
    static var aiVolcengineInvalidImage: String {
        text("ai_volcengine_invalid_image")
    }
    static var marketplaceSubtitle: String { text("marketplace_subtitle") }
    static var marketplaceLoading: String { text("marketplace_loading") }
    static var marketplaceUnavailable: String { text("marketplace_unavailable") }
    static var marketplaceSearch: String { text("marketplace_search") }
    static var marketplaceCount: String { text("marketplace_count") }
    static var marketplaceSource: String { text("marketplace_source") }
    static var marketplaceRightsNotice: String { text("marketplace_rights_notice") }
    static var addSource: String { text("add_source") }
    static var sourceType: String { text("source_type") }
    static var githubRepository: String { text("github_repository") }
    static var staticManifest: String { text("static_manifest") }
    static var owner: String { text("owner") }
    static var repository: String { text("repository") }
    static var branch: String { text("branch") }
    static var sourceName: String { text("source_name") }
    static var manifestURL: String { text("manifest_url") }
    static var add: String { text("add") }
    static var category: String { text("category") }
    static var allCategories: String { text("all_categories") }
    static var preview: String { text("preview") }
    static var download: String { text("download") }
    static var applyWallpaperShort: String { text("apply_wallpaper_short") }
    static var retry: String { text("retry") }
    static var close: String { text("close") }
    static var effectsSubtitle: String { text("effects_subtitle") }
    static var metalPowered: String { text("metal_powered") }
    static var particlesTitle: String { text("particles_title") }
    static var particlesDescription: String { text("particles_description") }
    static var waterTitle: String { text("water_title") }
    static var waterDescription: String { text("water_description") }
    static var interactiveTitle: String { text("interactive_title") }
    static var interactiveDescription: String { text("interactive_description") }
    static var applyEffect: String { text("apply_effect") }
    static var particleDemoTitle: String { text("particle_demo_title") }
    static var particleDemoDescription: String { text("particle_demo_description") }
    static var particleSettings: String { text("particle_settings") }
    static var particleQuality: String { text("particle_quality") }
    static var powerSaver: String { text("power_saver") }
    static var balanced: String { text("balanced") }
    static var highQuality: String { text("high_quality") }
    static var particleCount: String { text("particle_count") }
    static var particleSize: String { text("particle_size") }
    static var interactionRadius: String { text("interaction_radius") }
    static var forceStrength: String { text("force_strength") }
    static var returnSpeed: String { text("return_speed") }
    static var trailLength: String { text("trail_length") }
    static var targetFPS: String { text("target_fps") }
    static var optionInteractionHint: String { text("option_interaction_hint") }
    static var settings: String { text("settings") }
    static var reload: String { text("reload") }
    static var wallpapers: String { text("wallpapers") }
    static var videoCount: String { text("video_count") }
    static var selectWallpaperFolder: String { text("select_wallpaper_folder") }
    static var emptyLibraryTitle: String { text("empty_library_title") }
    static var emptyLibraryMessage: String { text("empty_library_message") }
    static var generating: String { text("generating") }
    static var displays: String { text("displays") }
    static var displayHint: String { text("display_hint") }
    static var allDisplays: String { text("all_displays") }
    static var selected: String { text("selected") }
    static var applyWallpaper: String { text("apply_wallpaper") }
    static var general: String { text("general") }
    static var playback: String { text("playback") }
    static var automation: String { text("automation") }
    static var maintenance: String { text("maintenance") }
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
    static var launchAtLogin: String { text("launch_at_login") }
    static var launchAtLoginHint: String { text("launch_at_login_hint") }
    static var randomOnStartup: String { text("random_on_startup") }
    static var randomOnLid: String { text("random_on_lid") }
    static var pauseWhenActive: String { text("pause_when_active") }
    static var performance: String { text("performance") }
    static var batteryMode: String { text("battery_mode") }
    static var batteryModeHint: String { text("battery_mode_hint") }
    static var lowPowerPause: String { text("low_power_pause") }
    static var lowPowerPauseHint: String { text("low_power_pause_hint") }
    static var fullScreenPause: String { text("fullscreen_pause") }
    static var fullScreenPauseHint: String { text("fullscreen_pause_hint") }
    static var renderFrameRate: String { text("render_frame_rate") }
    static var renderFrameRateHint: String { text("render_frame_rate_hint") }
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
    static var comingSoon: String { text("coming_soon") }
    static var clearCache: String { text("clear_cache") }
    static var clearCacheHint: String { text("clear_cache_hint") }
    static var resetUserData: String { text("reset_user_data") }
    static var resetUserDataHint: String { text("reset_user_data_hint") }
    static var reset: String { text("reset") }
    static var selectFolderTitle: String { text("select_folder_title") }
    static var choose: String { text("choose") }
    static var selectFolderOrType: String { text("select_folder_or_type") }
    static var showWindow: String { text("show_window") }
    static var hideWindow: String { text("hide_window") }
    static var quit: String { text("quit") }
}

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

// MARK: - Root navigation

private enum AppSection: String, CaseIterable, Identifiable {
    case library
    case web
    case marketplace
    case ai
    case effects
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .library: L.library
        case .web: "网页壁纸"
        case .marketplace: L.marketplace
        case .ai: L.aiWallpaper
        case .effects: L.effects
        case .settings: L.settings
        }
    }

    var symbol: String {
        switch self {
        case .library: "photo.on.rectangle.angled"
        case .web: "globe.americas.fill"
        case .marketplace: "square.grid.2x2"
        case .ai: "wand.and.stars"
        case .effects: "sparkles.rectangle.stack"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = WallpaperViewModel()
    @StateObject private var displayManager = DisplayManager()
    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var section: AppSection? = .library
    @State private var selectedVideoID: VideoItem.ID?
    @Environment(\.dismiss) private var dismiss

    static var didCloseOnLaunch = false

    var body: some View {
        NavigationSplitView {
            AppSidebar(selection: $section, videoCount: viewModel.videos.count)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            Group {
                switch section ?? .library {
                case .library:
                    WallpaperLibraryView(
                        viewModel: viewModel,
                        displayManager: displayManager,
                        selectedVideoID: $selectedVideoID
                    )
                case .web:
                    WebWallpaperView(
                        viewModel: viewModel,
                        displayManager: displayManager
                    )
                case .marketplace:
                    MarketplaceView(
                        libraryViewModel: viewModel,
                        displayManager: displayManager
                    )
                case .ai:
                    AIWallpaperView(
                        libraryViewModel: viewModel,
                        displayManager: displayManager
                    )
                case .effects:
                    ShaderEffectsView(
                        viewModel: viewModel,
                        displayManager: displayManager
                    )
                case .settings:
                    SettingsView(viewModel: viewModel)
                }
            }
            .id(languageManager.currentLanguage)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 860, minHeight: 560)
        .background(WindowBackdrop())
        .onAppear {
            viewModel.loadDisplays()
            displayManager.updateDisplays()
            viewModel.reloadContent()
            if !Self.didCloseOnLaunch, !AIWallpaperEngine.shared.isFirstLaunch() {
                Self.didCloseOnLaunch = true
                dismiss()
            }
        }
    }
}

// MARK: - Web wallpaper

private struct WebWallpaperView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @ObservedObject var displayManager: DisplayManager
    @State private var address = ""
    @State private var selectedLocalPage: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Label("网页壁纸", systemImage: "globe.americas.fill")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("支持已接入 AIWallpaperBridge 的在线网页、本地 HTML、Three.js 与 WebGL 壁纸。")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("在线网页")
                    .font(.headline)
                HStack(spacing: 12) {
                    TextField("https://your-domain.com/wallpaper", text: $address)
                        .textFieldStyle(.roundedBorder)
                    Button("应用") { applyRemotePage() }
                        .buttonStyle(.borderedProminent)
                        .disabled(validRemoteURL == nil)
                }
                Text("在线网页需要实现 AIWallpaperBridge 才能获得客户端输入数据。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .glassCard()

            VStack(alignment: .leading, spacing: 14) {
                Text("本地网页包")
                    .font(.headline)
                HStack(spacing: 12) {
                    Text(selectedLocalPage?.path ?? "选择一个 index.html 或其他 HTML 文件")
                        .lineLimit(1)
                        .foregroundStyle(selectedLocalPage == nil ? .secondary : .primary)
                    Spacer()
                    Button("选择 HTML…") { chooseLocalPage() }
                    Button("应用") { applyLocalPage() }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedLocalPage == nil)
                }
                Text("网页包可以包含 JavaScript、CSS、图片、Shader 与 Three.js 资源。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .glassCard()

            DisplaySelector(
                displays: displayManager.displays,
                selectedDisplays: $displayManager.selectedDisplays
            )
            Spacer()
        }
        .padding(28)
        .background(WindowBackdrop())
    }

    private var validRemoteURL: URL? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func applyRemotePage() {
        guard let validRemoteURL else { return }
        viewModel.startWebWallpaper(
            sourceURL: validRemoteURL,
            displays: Array(displayManager.selectedDisplays)
        )
    }

    private func chooseLocalPage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.html]
        panel.title = "选择网页壁纸"
        panel.prompt = "选择"
        if panel.runModal() == .OK { selectedLocalPage = panel.url }
    }

    private func applyLocalPage() {
        guard let selectedLocalPage else { return }
        viewModel.startWebWallpaper(
            sourceURL: selectedLocalPage,
            displays: Array(displayManager.selectedDisplays)
        )
    }
}

private struct WindowBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [Color.accentColor.opacity(0.12), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 620
            )
        }
        .ignoresSafeArea()
    }
}

private struct AppSidebar: View {
    @Binding var selection: AppSection?
    let videoCount: Int

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(AppSection.allCases) { section in
                    Label {
                        HStack {
                            Text(section.title)
                            Spacer()
                            if section == .library, videoCount > 0 {
                                Text("\(videoCount)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: section.symbol)
                    }
                    .tag(Optional(section))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 11) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text("AIWallpaperEngineMac")
                        .font(.headline)
                        .lineLimit(1)
                    Text("MP4 · GIF · Live Photo")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
    }
}

// MARK: - Metal shader effects

private struct ShaderEffectsView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @ObservedObject var displayManager: DisplayManager

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 18)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.effects)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(L.effectsSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label(L.metalPowered, systemImage: "cpu")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            Divider().opacity(0.55)

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ParticleDemoCard(isSelected: viewModel.isParticleDemoActive) {
                        viewModel.startParticleDemo(
                            displays: Array(displayManager.selectedDisplays)
                        )
                    }

                    ForEach(MetalShaderPreset.allCases) { preset in
                        ShaderEffectCard(
                            preset: preset,
                            isSelected: viewModel.activeShaderPreset == preset
                        ) {
                            viewModel.startMetalEffect(
                                preset,
                                displays: Array(displayManager.selectedDisplays)
                            )
                        }
                    }
                }
                .padding(28)

                if let message = viewModel.rendererErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.55)

            DisplaySelector(
                displays: displayManager.displays,
                selectedDisplays: $displayManager.selectedDisplays
            )
        }
        .background(WindowBackdrop())
    }
}

private struct ParticleDemoCard: View {
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    LinearGradient(
                        colors: [.black, Color(red: 0.01, green: 0.08, blue: 0.16)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    Text("AI")
                        .font(.system(size: 62, weight: .black, design: .rounded))
                        .foregroundStyle(.cyan)
                        .blur(radius: 8)
                        .opacity(0.65)
                    Text("AI")
                        .font(.system(size: 62, weight: .black, design: .rounded))
                        .foregroundStyle(.white, .cyan)
                    ForEach(0..<24, id: \.self) { index in
                        Circle()
                            .fill(index.isMultiple(of: 3) ? Color.white : Color.cyan)
                            .frame(width: 2.5 + CGFloat(index % 3), height: 2.5 + CGFloat(index % 3))
                            .shadow(color: .cyan, radius: 4)
                            .offset(
                                x: CGFloat((index * 53) % 230 - 115),
                                y: CGFloat((index * 29) % 110 - 55)
                            )
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipped()

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.particleDemoTitle).font(.headline)
                        Text(L.particleDemoDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(14)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : .white.opacity(isHovering ? 0.24 : 0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .shadow(color: .black.opacity(isHovering ? 0.22 : 0.09), radius: 16, y: 8)
            .scaleEffect(isHovering ? 1.012 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) { isHovering = hovering }
        }
        .help(String(format: L.applyEffect, L.particleDemoTitle))
    }
}

private struct ShaderEffectCard: View {
    let preset: MetalShaderPreset
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    LinearGradient(
                        colors: palette,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    previewArtwork

                    if isHovering {
                        ZStack {
                            Circle().fill(.ultraThinMaterial)
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .frame(width: 44, height: 44)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipped()

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(14)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : .white.opacity(isHovering ? 0.24 : 0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .shadow(color: .black.opacity(isHovering ? 0.22 : 0.09), radius: 16, y: 8)
            .scaleEffect(isHovering ? 1.012 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHovering = hovering
            }
        }
        .help(String(format: L.applyEffect, title))
    }

    @ViewBuilder
    private var previewArtwork: some View {
        switch preset {
        case .particles:
            ZStack {
                ForEach(0..<15, id: \.self) { index in
                    Circle()
                        .fill(index.isMultiple(of: 3) ? Color.cyan : Color.white)
                        .frame(width: CGFloat(3 + index % 5), height: CGFloat(3 + index % 5))
                        .blur(radius: index.isMultiple(of: 2) ? 1.5 : 0)
                        .offset(
                            x: CGFloat((index * 47) % 210 - 105),
                            y: CGFloat((index * 31) % 100 - 50)
                        )
                }
            }
        case .water:
            ZStack {
                ForEach(0..<5, id: \.self) { index in
                    Ellipse()
                        .stroke(Color.cyan.opacity(0.65 - Double(index) * 0.1), lineWidth: 2)
                        .frame(width: CGFloat(48 + index * 34), height: CGFloat(22 + index * 16))
                }
            }
        case .interactive:
            ZStack {
                ForEach(0..<7, id: \.self) { index in
                    Circle()
                        .trim(from: 0.08, to: 0.82)
                        .stroke(
                            Color(hue: Double(index) / 8.0, saturation: 0.7, brightness: 1),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: CGFloat(34 + index * 22), height: CGFloat(34 + index * 22))
                        .rotationEffect(.degrees(Double(index * 39)))
                }
            }
        }
    }

    private var title: String {
        switch preset {
        case .particles: L.particlesTitle
        case .water: L.waterTitle
        case .interactive: L.interactiveTitle
        }
    }

    private var description: String {
        switch preset {
        case .particles: L.particlesDescription
        case .water: L.waterDescription
        case .interactive: L.interactiveDescription
        }
    }

    private var palette: [Color] {
        switch preset {
        case .particles: [.black, .indigo, .blue.opacity(0.8)]
        case .water: [.indigo.opacity(0.9), .blue, .cyan]
        case .interactive: [.black, .purple, .pink.opacity(0.8)]
        }
    }
}

// MARK: - Wallpaper library

private struct WallpaperLibraryView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @ObservedObject var displayManager: DisplayManager
    @Binding var selectedVideoID: VideoItem.ID?

    var body: some View {
        VStack(spacing: 0) {
            LibraryHeader(videoCount: viewModel.videos.count) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.reloadContent()
                }
            }

            Divider().opacity(0.55)

            VideoGridView(
                videos: viewModel.videos,
                viewModel: viewModel,
                selectedVideoID: $selectedVideoID
            ) { video in
                selectedVideoID = video.id
                viewModel.startWallpaper(
                    video: video,
                    displays: Array(displayManager.selectedDisplays)
                )
            }

            Divider().opacity(0.55)

            DisplaySelector(
                displays: displayManager.displays,
                selectedDisplays: $displayManager.selectedDisplays
            )
        }
        .background(WindowBackdrop())
    }
}

private struct LibraryHeader: View {
    let videoCount: Int
    let onReload: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.library)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(L.librarySubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if videoCount > 0 {
                Text(String(format: L.videoCount, videoCount))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.quaternary, in: Capsule())
            }

            Button(action: onReload) {
                Label(L.reload, systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help(L.reload)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }
}

private struct VideoGridView: View {
    let videos: [VideoItem]
    let viewModel: WallpaperViewModel
    @Binding var selectedVideoID: VideoItem.ID?
    let onVideoSelect: (VideoItem) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 230, maximum: 360), spacing: 18)
    ]

    var body: some View {
        ScrollView {
            if videos.isEmpty {
                EmptyLibraryView(onChooseFolder: chooseFolder)
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .padding(32)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(videos) { video in
                        VideoCard(
                            video: video,
                            isSelected: selectedVideoID == video.id
                        ) {
                            onVideoSelect(video)
                        }
                    }
                }
                .padding(28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseFolder() {
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
}

private struct EmptyLibraryView: View {
    let onChooseFolder: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: "film.stack")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 78, height: 78)

            VStack(spacing: 7) {
                Text(L.emptyLibraryTitle)
                    .font(.title2.bold())
                Text(L.emptyLibraryMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 390)
            }

            Button(action: onChooseFolder) {
                Label(L.selectWallpaperFolder, systemImage: "folder.badge.plus")
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

private struct VideoCard: View {
    let video: VideoItem
    let isSelected: Bool
    let action: () -> Void
    @ObservedObject private var cache = ThumbnailCache.shared
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    let _ = cache.lastUpdate

                    Group {
                        if let thumbnail = video.loadThumbnail() {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .aspectRatio(16 / 9, contentMode: .fill)
                        } else {
                            Rectangle()
                                .fill(.quaternary)
                                .overlay {
                                    VStack(spacing: 7) {
                                        ProgressView().controlSize(.small)
                                        Text(L.generating)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                        }
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipped()

                    if let quality = video.quality, !quality.isEmpty {
                        QualityBadge(text: quality)
                            .padding(10)
                    }

                    if isHovering {
                        ZStack {
                            Circle().fill(.ultraThinMaterial)
                            Image(systemName: "play.fill")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .frame(width: 42, height: 42)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .transition(.scale.combined(with: .opacity))
                    }
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text((video.filename as NSString).deletingPathExtension)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text(video.formatLabel)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isSelected {
                        Label(L.selected, systemImage: "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 16))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(12)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : .white.opacity(isHovering ? 0.24 : 0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .shadow(
                color: .black.opacity(isHovering ? 0.2 : 0.08),
                radius: isHovering ? 18 : 8,
                y: isHovering ? 10 : 4
            )
            .scaleEffect(isHovering ? 1.012 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHovering = hovering
            }
        }
        .help(String(format: L.applyWallpaper, video.filename))
        .accessibilityLabel(String(format: L.applyWallpaper, video.filename))
    }
}

private struct QualityBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(0.62), in: Capsule())
    }
}

// MARK: - Display selection

struct DisplaySelector: View {
    let displays: [DisplayObjc]
    @Binding var selectedDisplays: Set<UInt32>

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Label(L.displays, systemImage: "display.2")
                    .font(.headline)
                Text(L.displayHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 150, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    DisplayChoice(
                        name: L.allDisplays,
                        resolution: "\(displays.count)",
                        symbol: "rectangle.on.rectangle",
                        isSelected: selectedDisplays.isEmpty
                    ) {
                        withAnimation(.snappy(duration: 0.25)) {
                            selectedDisplays.removeAll()
                        }
                    }

                    ForEach(displays, id: \.screen) { display in
                        DisplayChoice(
                            name: display.getDisplayName(),
                            resolution: display.getResolution(),
                            symbol: "display",
                            isSelected: selectedDisplays.contains(display.screen)
                        ) {
                            withAnimation(.snappy(duration: 0.25)) {
                                if selectedDisplays.contains(display.screen) {
                                    selectedDisplays.remove(display.screen)
                                } else {
                                    selectedDisplays.insert(display.screen)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }
}

private struct DisplayChoice: View {
    let name: String
    let resolution: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(resolution)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.75) : .white.opacity(0.1),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var viewModel: WallpaperViewModel
    @ObservedObject private var languageManager = LanguageManager.shared
    @ObservedObject private var particleSettings = ParticleSettingsStore.shared
    @ObservedObject private var performanceSettings = PerformanceSettingsStore.shared

    @AppStorage(UserDefaultsKeys.scaleMode) private var scaleMode = 0
    @AppStorage(UserDefaultsKeys.randomOnStartup) private var randomOnStartup = false
    @AppStorage(UserDefaultsKeys.randomOnLid) private var randomOnLid = false
    @AppStorage(UserDefaultsKeys.pauseOnAppFocus) private var pauseOnAppFocus = true
    @AppStorage(UserDefaultsKeys.vignetteBar) private var vignetteBar = true
    @AppStorage(UserDefaultsKeys.rotation) private var rotationEnabled = false

    @State private var localMinutes = 60
    @State private var launchAtLogin = isLoginItemEnabled()
    @State private var systemAudioReactive = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.settings)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(L.appName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                SettingsSection(title: "音乐特效", symbol: "waveform") {
                    SettingLine(title: "跟随系统音乐", symbol: "music.note") {
                        Toggle("", isOn: $systemAudioReactive)
                            .labelsHidden()
                            .onChange(of: systemAudioReactive) { _, enabled in
                                if enabled {
                                    MusicEffectEngine.shared.startSystemAudio()
                                } else {
                                    MusicEffectEngine.shared.stopSystemAudio()
                                }
                            }
                    }
                    Text("开启后，网易云音乐、Apple Music、Spotify 和浏览器的声音可驱动粒子效果。macOS 会请求屏幕录制权限；不会读取账号或保存音频。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsSection(title: L.general, symbol: "slider.horizontal.3") {
                    SettingLine(title: L.wallpaperFolder, symbol: "folder") {
                        HStack(spacing: 8) {
                            TextField(L.selectFolderOrType, text: $viewModel.folderPath)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 220)
                                .onSubmit { applyFolderPath() }

                            Button(action: selectFolder) {
                                Image(systemName: "folder.badge.plus")
                            }
                            .help(L.selectFolder)

                            Button(action: openInFinder) {
                                Image(systemName: "arrow.forward.square")
                            }
                            .help(L.showInFinder)
                        }
                    }

                    SettingsDivider()

                    SettingLine(title: L.appLanguage, symbol: "character.bubble") {
                        Picker("", selection: languageBinding) {
                            Text(L.systemLanguage).tag("auto")
                            Text("简体中文").tag("zh-Hans")
                            Text("English").tag("en")
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }

                    SettingsDivider()

                    SettingLine(
                        title: L.launchAtLogin,
                        subtitle: L.launchAtLoginHint,
                        symbol: "power"
                    ) {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: launchAtLogin) { _, enabled in
                                setLoginItem(enabled: enabled)
                                launchAtLogin = isLoginItemEnabled()
                            }
                    }
                }

                SettingsSection(title: L.playback, symbol: "play.rectangle") {
                    SettingLine(title: L.videoScalingMode, symbol: "arrow.up.left.and.arrow.down.right") {
                        Picker("", selection: $scaleMode) {
                            Text(L.scaleFill).tag(0)
                            Text(L.scaleFit).tag(1)
                            Text(L.scaleStretch).tag(2)
                            Text(L.scaleCenter).tag(3)
                            Text(L.scaleHeightFill).tag(4)
                        }
                        .labelsHidden()
                        .frame(width: 170)
                        .onChange(of: scaleMode) { _, newValue in
                            viewModel.engine.updateScaleMode(newValue)
                        }
                    }

                    SettingsDivider()

                    SettingLine(title: L.videoVolume, symbol: "speaker.wave.2") {
                        HStack(spacing: 12) {
                            Slider(value: $viewModel.volume, in: 0...100, step: 1)
                                .frame(minWidth: 150, idealWidth: 220)
                                .onChange(of: viewModel.volume) { _, newValue in
                                    viewModel.engine.updateVolume(newValue)
                                }
                            Text("\(Int(viewModel.volume))%")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }

                    SettingsDivider()

                    SettingLine(title: L.pauseWhenActive, symbol: "pause.circle") {
                        SettingsToggle(isOn: $pauseOnAppFocus)
                    }

                    SettingsDivider()

                    SettingLine(title: L.vignetteBar, symbol: "circle.lefthalf.filled") {
                        SettingsToggle(isOn: $vignetteBar)
                    }
                }

                SettingsSection(title: L.performance, symbol: "bolt.gauge") {
                    SettingLine(
                        title: L.batteryMode,
                        subtitle: L.batteryModeHint,
                        symbol: "battery.75percent"
                    ) {
                        SettingsToggle(isOn: $performanceSettings.batteryModeEnabled)
                    }

                    SettingsDivider()

                    SettingLine(
                        title: L.lowPowerPause,
                        subtitle: L.lowPowerPauseHint,
                        symbol: "battery.25percent"
                    ) {
                        SettingsToggle(isOn: $performanceSettings.pauseInLowPowerMode)
                    }

                    SettingsDivider()

                    SettingLine(
                        title: L.fullScreenPause,
                        subtitle: L.fullScreenPauseHint,
                        symbol: "rectangle.inset.filled"
                    ) {
                        SettingsToggle(isOn: $performanceSettings.pauseForFullScreenApps)
                    }

                    SettingsDivider()

                    SettingLine(
                        title: L.renderFrameRate,
                        subtitle: L.renderFrameRateHint,
                        symbol: "speedometer"
                    ) {
                        Picker("", selection: $performanceSettings.targetFPS) {
                            Text("24 FPS").tag(24)
                            Text("30 FPS").tag(30)
                            Text("60 FPS").tag(60)
                            Text("120 FPS").tag(120)
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }

                SettingsSection(title: L.particleSettings, symbol: "sparkles") {
                    SettingLine(
                        title: L.particleQuality,
                        subtitle: L.optionInteractionHint,
                        symbol: "gauge.with.dots.needle.50percent"
                    ) {
                        Picker("", selection: particlePresetBinding) {
                            Text(L.powerSaver).tag(ParticleQualityPreset.powerSaver)
                            Text(L.balanced).tag(ParticleQualityPreset.balanced)
                            Text(L.highQuality).tag(ParticleQualityPreset.highQuality)
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }

                    SettingsDivider()

                    SettingLine(title: L.particleCount, symbol: "circle.grid.3x3.fill") {
                        HStack(spacing: 12) {
                            Slider(value: particleCountBinding, in: 10_000...250_000, step: 10_000)
                                .frame(width: 220)
                            Text("\(particleSettings.particleCount.formatted())")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 72, alignment: .trailing)
                        }
                    }

                    SettingsDivider()
                    particleSlider(
                        title: L.particleSize,
                        symbol: "circle.fill",
                        value: $particleSettings.particleSize,
                        range: 1...8,
                        format: "%.1f px"
                    )
                    SettingsDivider()
                    particleSlider(
                        title: L.interactionRadius,
                        symbol: "dot.scope",
                        value: $particleSettings.interactionRadius,
                        range: 0.08...0.8,
                        format: "%.2f"
                    )
                    SettingsDivider()
                    particleSlider(
                        title: L.forceStrength,
                        symbol: "arrow.up.and.down.and.arrow.left.and.right",
                        value: $particleSettings.forceStrength,
                        range: -6...6,
                        format: "%+.1f"
                    )
                    SettingsDivider()
                    particleSlider(
                        title: L.returnSpeed,
                        symbol: "arrow.uturn.backward.circle",
                        value: $particleSettings.returnSpeed,
                        range: 0.05...3,
                        format: "%.2f"
                    )
                    SettingsDivider()
                    particleSlider(
                        title: L.trailLength,
                        symbol: "wind",
                        value: $particleSettings.trailLength,
                        range: 0...2,
                        format: "%.2f"
                    )
                    SettingsDivider()
                    SettingLine(title: L.targetFPS, symbol: "speedometer") {
                        Picker("", selection: $particleSettings.targetFPS) {
                            Text("30 FPS").tag(30)
                            Text("60 FPS").tag(60)
                            Text("120 FPS").tag(120)
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        .onChange(of: particleSettings.targetFPS) { _, _ in
                            particleSettings.markCustom()
                        }
                    }
                }

                SettingsSection(title: L.automation, symbol: "clock.arrow.circlepath") {
                    SettingLine(title: L.randomOnStartup, symbol: "shuffle") {
                        SettingsToggle(isOn: $randomOnStartup)
                    }

                    SettingsDivider()

                    SettingLine(title: L.randomOnLid, symbol: "wake") {
                        SettingsToggle(isOn: $randomOnLid)
                    }

                    SettingsDivider()

                    SettingLine(title: L.wallpaperRotation, symbol: "rectangle.3.group") {
                        Toggle("", isOn: $rotationEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: rotationEnabled) { _, enabled in
                                viewModel.engine.isRotationRunning = enabled
                                if enabled {
                                    viewModel.engine.startWallpaperRotation()
                                } else {
                                    viewModel.engine.stopWallpaperRotation()
                                }
                            }
                    }

                    SettingsDivider()

                    SettingLine(title: L.rotationDelay, symbol: "timer") {
                        HStack(spacing: 10) {
                            Stepper(value: $localMinutes, in: 1...1440, step: 4) {
                                Text(formatTime(localMinutes))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .onChange(of: localMinutes) { _, newValue in
                                let seconds = newValue * 60
                                viewModel.engine.rotationDelay = Int32(seconds)
                                UserDefaults.standard.set(seconds, forKey: UserDefaultsKeys.rdelay)
                            }
                        }
                    }

                    SettingsDivider()

                    SettingLine(title: L.rotationType, symbol: "arrow.triangle.2.circlepath") {
                        Picker("", selection: rotationTypeBinding) {
                            Text(L.rotationSequential).tag(RotationType.sequential)
                            Text(L.rotationRandom).tag(RotationType.random)
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                }

                SettingsSection(title: L.maintenance, symbol: "wrench.and.screwdriver") {
                    SettingLine(
                        title: L.optimizeCodecs,
                        subtitle: L.comingSoon,
                        symbol: "bolt"
                    ) {
                        Button(L.optimize) { viewModel.optimizeVideos() }
                            .disabled(true)
                    }

                    SettingsDivider()

                    SettingLine(
                        title: L.clearCache,
                        subtitle: L.clearCacheHint,
                        symbol: "trash"
                    ) {
                        Button(L.clearCache) { viewModel.clearCache() }
                    }

                    SettingsDivider()

                    SettingLine(
                        title: L.resetUserData,
                        subtitle: L.resetUserDataHint,
                        symbol: "arrow.counterclockwise"
                    ) {
                        Button(L.reset, role: .destructive) { viewModel.resetUserData() }
                    }
                }
            }
            .frame(maxWidth: 820)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(WindowBackdrop())
        .onAppear {
            let storedDelay = UserDefaults.standard.integer(forKey: UserDefaultsKeys.rdelay) / 60
            localMinutes = max(1, storedDelay == 0 ? 60 : storedDelay)
            launchAtLogin = isLoginItemEnabled()
        }
    }

    private var languageBinding: Binding<String> {
        Binding(
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
    }

    private var particlePresetBinding: Binding<ParticleQualityPreset> {
        Binding(
            get: { particleSettings.selectedPreset ?? .balanced },
            set: { particleSettings.apply($0) }
        )
    }

    private var particleCountBinding: Binding<Double> {
        Binding(
            get: { Double(particleSettings.particleCount) },
            set: {
                particleSettings.particleCount = Int($0)
                particleSettings.markCustom()
            }
        )
    }

    private func particleSlider(
        title: String,
        symbol: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
        SettingLine(title: title, symbol: symbol) {
            HStack(spacing: 12) {
                Slider(value: value, in: range)
                    .frame(width: 220)
                    .onChange(of: value.wrappedValue) { _, _ in
                        particleSettings.markCustom()
                    }
                Text(String(format: format, value.wrappedValue))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
            }
        }
    }

    private var rotationTypeBinding: Binding<RotationType> {
        Binding(
            get: { viewModel.engine.rotationType },
            set: { newValue in
                viewModel.engine.rotationType = newValue
                UserDefaults.standard.set(
                    newValue == .sequential ? 1 : 2,
                    forKey: UserDefaultsKeys.rtype
                )
            }
        )
    }

    private func formatTime(_ totalMinutes: Int) -> String {
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return String(format: L.timeHoursMinutes, hours, minutes)
        }
        return String(format: L.timeMinutes, minutes)
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
            applyFolderPath()
        }
    }

    private func applyFolderPath() {
        guard !viewModel.folderPath.isEmpty else { return }
        viewModel.engine.selectFolder(viewModel.folderPath)
        viewModel.reloadContent()
    }

    private func openInFinder() {
        guard !viewModel.folderPath.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: viewModel.folderPath)])
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)
                .padding(.top, 17)
                .padding(.bottom, 12)

            content
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
        }
        .glassCard(cornerRadius: 18)
    }
}

private struct SettingLine<Content: View>: View {
    let title: String
    var subtitle: String?
    let symbol: String
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 18)
            content
        }
        .padding(.vertical, 8)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 38)
    }
}

private struct SettingsToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
    }
}

#Preview {
    ContentView()
        .frame(width: 1100, height: 720)
}
