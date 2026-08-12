import AppKit
import SwiftUI

struct AIWallpaperView: View {
    @ObservedObject var libraryViewModel: WallpaperViewModel
    @ObservedObject var displayManager: DisplayManager
    @StateObject private var viewModel = AIWallpaperGenerationViewModel()
    @ObservedObject private var keyStore = OpenAIAPIKeyStore.shared
    @ObservedObject private var volcengineKeyStore =
        VolcengineAPIKeyStore.shared
    @ObservedObject private var volcengineConfiguration =
        VolcengineConfigurationStore.shared
    @State private var generationTask: Task<Void, Never>?
    @State private var isConfiguringAPI = false
    @State private var isConfiguringVolcengine = false
    @State private var isConfirmingKeyRemoval = false
    @State private var isConfirmingVolcengineKeyRemoval = false
    @State private var keyManagementError: String?

    private let columns = [
        GridItem(.adaptive(minimum: 230, maximum: 330), spacing: 18)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.55)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    demoNotice
                    apiConnection
                    generator
                    history
                }
                .padding(28)
            }

            Divider().opacity(0.55)
            DisplaySelector(
                displays: displayManager.displays,
                selectedDisplays: $displayManager.selectedDisplays
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.history.removeMissingFiles()
            keyStore.refreshStatus()
            volcengineKeyStore.refreshStatus()
        }
        .onDisappear {
            generationTask?.cancel()
            generationTask = nil
        }
        .sheet(isPresented: $isConfiguringAPI) {
            OpenAIKeyConfigurationView(keyStore: keyStore)
        }
        .sheet(isPresented: $isConfiguringVolcengine) {
            VolcengineConfigurationView(
                keyStore: volcengineKeyStore,
                configuration: volcengineConfiguration
            )
        }
        .confirmationDialog(
            L.aiRemoveKeyTitle,
            isPresented: $isConfirmingKeyRemoval
        ) {
            Button(L.aiRemoveKey, role: .destructive) {
                do {
                    try keyStore.remove()
                    viewModel.selectedProviderID = viewModel.providers.first?.id ?? ""
                    keyManagementError = nil
                } catch {
                    keyManagementError = error.localizedDescription
                }
            }
            Button(L.close, role: .cancel) {}
        } message: {
            Text(L.aiRemoveKeyDescription)
        }
        .confirmationDialog(
            L.aiVolcengineRemoveKeyTitle,
            isPresented: $isConfirmingVolcengineKeyRemoval
        ) {
            Button(L.aiRemoveKey, role: .destructive) {
                do {
                    try volcengineKeyStore.remove()
                    if isVolcengineSelected {
                        viewModel.selectedProviderID =
                            viewModel.providers.first?.id ?? ""
                    }
                    keyManagementError = nil
                } catch {
                    keyManagementError = error.localizedDescription
                }
            }
            Button(L.close, role: .cancel) {}
        } message: {
            Text(L.aiVolcengineRemoveKeyDescription)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.aiWallpaper)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(L.aiWallpaperSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(
                viewModel.selectedProvider?.displayName ?? "",
                systemImage: "cpu"
            )
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.thinMaterial, in: Capsule())
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var demoNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(
                systemName: viewModel.selectedProvider?.isDemo == false
                    ? "network" : "wand.and.stars"
            )
                .font(.title3)
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    isVolcengineSelected
                        ? L.aiVolcengineMode
                        : (
                            viewModel.selectedProvider?.isDemo == false
                                ? L.aiOpenAIMode : L.aiDemoMode
                        )
                )
                    .font(.headline)
                Text(
                    isVolcengineSelected
                        ? L.aiVolcengineModeDescription
                        : (
                            viewModel.selectedProvider?.isDemo == false
                                ? L.aiOpenAIModeDescription
                                : L.aiDemoModeDescription
                        )
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.cyan.opacity(0.2))
        }
    }

    private var apiConnection: some View {
        VStack(alignment: .leading, spacing: 14) {
            connectionRow(
                title: L.aiOpenAIConnection,
                hasKey: keyStore.hasKey,
                maskedKey: keyStore.maskedKey,
                detail: nil,
                configure: { isConfiguringAPI = true },
                remove: { isConfirmingKeyRemoval = true }
            )

            Divider()

            connectionRow(
                title: L.aiVolcengineConnection,
                hasKey: volcengineKeyStore.hasKey,
                maskedKey: volcengineKeyStore.maskedKey,
                detail: volcengineConfiguration.modelID,
                configure: { isConfiguringVolcengine = true },
                remove: { isConfirmingVolcengineKeyRemoval = true }
            )

            if let keyManagementError {
                Text(keyManagementError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 18)
    }

    private func connectionRow(
        title: String,
        hasKey: Bool,
        maskedKey: String,
        detail: String?,
        configure: @escaping () -> Void,
        remove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(
                systemName: hasKey
                    ? "checkmark.shield.fill" : "key.slash"
            )
            .font(.title3)
            .foregroundStyle(hasKey ? .green : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(
                    hasKey
                        ? String(format: L.aiKeyConfigured, maskedKey)
                        : L.aiKeyNotConfigured
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(hasKey ? L.aiReplaceKey : L.aiConfigureKey) {
                configure()
            }
            .buttonStyle(.borderedProminent)

            if hasKey {
                Button(L.aiRemoveKey, role: .destructive) {
                    remove()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var generator: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L.aiDescribeWallpaper, systemImage: "text.bubble")
                .font(.headline)

            TextField(L.aiPromptPlaceholder, text: $viewModel.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...7)
                .padding(14)
                .background(
                    Color.primary.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 13)
                )

            HStack(spacing: 14) {
                Picker(L.aiProvider, selection: $viewModel.selectedProviderID) {
                    ForEach(viewModel.providers, id: \.id) { provider in
                        Text(provider.displayName).tag(provider.id)
                    }
                }
                .frame(width: 210)

                Picker(L.aiStyle, selection: $viewModel.style) {
                    ForEach(AIWallpaperStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .frame(width: 220)

                Label(
                    isVolcengineSelected
                        ? "2048 × 1152"
                        : (
                            viewModel.selectedProvider?.isDemo == false
                                ? "1536 × 1024" : "1792 × 1024"
                        ),
                    systemImage: "rectangle.ratio.16.to.9"
                )
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                if viewModel.isGenerating {
                    Button(role: .cancel) {
                        generationTask?.cancel()
                    } label: {
                        Label(L.aiCancelGeneration, systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Button {
                    generationTask = Task {
                        guard
                            await viewModel.generate(
                                folderPath: libraryViewModel.folderPath
                            ) != nil
                        else {
                            return
                        }
                        libraryViewModel.reloadContent()
                    }
                } label: {
                    if viewModel.isGenerating {
                        ProgressView()
                            .controlSize(.small)
                        Text(L.aiGenerating)
                    } else {
                        Label(L.aiGenerate, systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(
                    viewModel.isGenerating
                        || viewModel.prompt.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                        || libraryViewModel.folderPath.isEmpty
                        || (isOpenAISelected && !keyStore.hasKey)
                        || (
                            isVolcengineSelected
                                && !volcengineKeyStore.hasKey
                        )
                )
            }

            if let errorMessage = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.callout)
                    Spacer()
                    Button {
                        viewModel.clearError()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 18)
    }

    @ViewBuilder
    private var history: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L.aiGenerationHistory, systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.history.items.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if viewModel.history.items.isEmpty {
                ContentUnavailableView {
                    Label(L.aiNoHistory, systemImage: "photo.badge.plus")
                } description: {
                    Text(L.aiNoHistoryDescription)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .glassCard(cornerRadius: 18)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(viewModel.history.items) { result in
                        historyCard(result)
                    }
                }
            }
        }
    }

    private func historyCard(
        _ result: AIWallpaperGenerationResult
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = NSImage(contentsOf: result.localURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 150)
                    .clipped()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 150)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(result.prompt)
                    .font(.headline)
                    .lineLimit(2)
                HStack {
                    Text(result.style.title)
                    Spacer()
                    Text(result.createdAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([
                            result.localURL
                        ])
                    } label: {
                        Label(L.showInFinder, systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        apply(result)
                    } label: {
                        Label(
                            L.applyWallpaperShort,
                            systemImage: "desktopcomputer"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
        }
        .glassCard(cornerRadius: 17)
        .clipShape(RoundedRectangle(cornerRadius: 17))
    }

    private func apply(_ result: AIWallpaperGenerationResult) {
        let item = VideoItem(
            filename: result.localURL.lastPathComponent,
            path: result.localPath,
            thumbnailPath: "",
            kind: .image,
            thumbnailSourcePath: result.localPath
        )
        libraryViewModel.startWallpaper(
            video: item,
            displays: Array(displayManager.selectedDisplays)
        )
    }

    private var isOpenAISelected: Bool {
        viewModel.selectedProviderID == "ai.openai.image"
    }

    private var isVolcengineSelected: Bool {
        viewModel.selectedProviderID == "ai.volcengine.seedream"
    }
}

private struct OpenAIKeyConfigurationView: View {
    @ObservedObject var keyStore: OpenAIAPIKeyStore
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var showsKey = false
    @State private var isValidating = false
    @State private var validationTask: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "key.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(keyStore.hasKey ? L.aiReplaceKey : L.aiConfigureKey)
                        .font(.title2.bold())
                    Text(L.aiKeySecurityDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Group {
                if showsKey {
                    TextField(L.aiAPIKeyPlaceholder, text: $apiKey)
                } else {
                    SecureField(L.aiAPIKeyPlaceholder, text: $apiKey)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced())

            Toggle(L.aiShowKey, isOn: $showsKey)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Text(L.aiAPIUsageNotice)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button(L.close) {
                    validationTask?.cancel()
                    validationTask = nil
                    apiKey = ""
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    validateAndSave()
                } label: {
                    if isValidating {
                        ProgressView()
                            .controlSize(.small)
                        Text(L.aiValidatingKey)
                    } else {
                        Label(L.aiValidateAndSave, systemImage: "checkmark.shield")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isValidating
                        || apiKey.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                )
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 520)
        .interactiveDismissDisabled(isValidating)
        .onDisappear {
            validationTask?.cancel()
            validationTask = nil
            apiKey = ""
        }
    }

    private func validateAndSave() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        isValidating = true
        errorMessage = nil
        validationTask = Task {
            defer {
                isValidating = false
                validationTask = nil
            }
            do {
                try await OpenAIWallpaperProvider(
                    keyStore: keyStore
                ).validateAPIKey(key)
                try Task.checkCancellation()
                try keyStore.save(key)
                apiKey = ""
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct VolcengineConfigurationView: View {
    @ObservedObject var keyStore: VolcengineAPIKeyStore
    @ObservedObject var configuration: VolcengineConfigurationStore
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var modelID = ""
    @State private var showsKey = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.aiVolcengineConfigure)
                        .font(.title2.bold())
                    Text(L.aiVolcengineSecurityDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(L.aiVolcengineKeyPlaceholder)
                    .font(.headline)
                Group {
                    if showsKey {
                        TextField(
                            L.aiVolcengineKeyPlaceholder,
                            text: $apiKey
                        )
                    } else {
                        SecureField(
                            L.aiVolcengineKeyPlaceholder,
                            text: $apiKey
                        )
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                Text(
                    keyStore.hasKey && apiKey.isEmpty
                        ? String(
                            format: L.aiKeyConfigured,
                            keyStore.maskedKey
                        )
                        : L.aiVolcengineSecurityDescription
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Toggle(L.aiShowKey, isOn: $showsKey)

            VStack(alignment: .leading, spacing: 7) {
                Text(L.aiVolcengineModelID)
                    .font(.headline)
                TextField(L.aiVolcengineModelHint, text: $modelID)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                Text(L.aiVolcengineModelHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Text(L.aiVolcengineUsageNotice)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button(L.close) {
                    apiKey = ""
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    saveConfiguration()
                } label: {
                    Label(
                        L.aiVolcengineSave,
                        systemImage: "checkmark.shield"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    modelID.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                        || (!keyStore.hasKey && apiKey.isEmpty)
                )
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 560)
        .onAppear {
            modelID = configuration.modelID
        }
        .onDisappear {
            apiKey = ""
        }
    }

    private func saveConfiguration() {
        errorMessage = nil
        do {
            if !apiKey.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty {
                try keyStore.save(apiKey)
            }
            try configuration.saveModelID(modelID)
            apiKey = ""
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
