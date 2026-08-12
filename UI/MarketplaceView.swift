import AVKit
import SwiftUI

struct MarketplaceView: View {
    @ObservedObject var libraryViewModel: WallpaperViewModel
    @ObservedObject var displayManager: DisplayManager
    @StateObject private var viewModel = MarketplaceViewModel()
    @ObservedObject private var downloadManager = WallpaperDownloadManager.shared
    @State private var previewWallpaper: MarketplaceWallpaper?
    @State private var isAddingSource = false

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 18)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.55)

            Group {
                if viewModel.isLoading && viewModel.wallpapers.isEmpty {
                    ProgressView(L.marketplaceLoading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = viewModel.errorMessage,
                    viewModel.wallpapers.isEmpty
                {
                    ContentUnavailableView {
                        Label(L.marketplaceUnavailable, systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button(L.retry) {
                            Task {
                                await viewModel.load(folderPath: libraryViewModel.folderPath)
                            }
                        }
                    }
                } else {
                    catalogGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.55)
            DisplaySelector(
                displays: displayManager.displays,
                selectedDisplays: $displayManager.selectedDisplays
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            if viewModel.wallpapers.isEmpty {
                await viewModel.load(folderPath: libraryViewModel.folderPath)
            }
        }
        .sheet(item: $previewWallpaper) { wallpaper in
            MarketplacePreviewView(wallpaper: wallpaper)
        }
        .sheet(isPresented: $isAddingSource) {
            AddWallpaperSourceView(viewModel: viewModel)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.marketplace)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(L.marketplaceSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isAddingSource = true
                } label: {
                    Label(L.addSource, systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        await viewModel.load(folderPath: libraryViewModel.folderPath)
                    }
                } label: {
                    Label(L.reload, systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoading)
            }

            HStack(spacing: 12) {
                Picker("", selection: $viewModel.selectedProviderID) {
                    ForEach(viewModel.providers, id: \.id) { provider in
                        Text(provider.displayName).tag(provider.id)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .onChange(of: viewModel.selectedProviderID) { _, _ in
                    Task {
                        await viewModel.load(folderPath: libraryViewModel.folderPath)
                    }
                }

                TextField(L.marketplaceSearch, text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)

                Picker(L.category, selection: $viewModel.selectedCategory) {
                    ForEach(viewModel.categories, id: \.self) { category in
                        Text(category == "all" ? L.allCategories : category).tag(category)
                    }
                }
                .frame(width: 180)

                Spacer()

                Text(String(format: L.marketplaceCount, viewModel.filteredWallpapers.count))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var catalogGrid: some View {
        ScrollView {
            if let errorMessage = viewModel.errorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.callout)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        viewModel.clearError()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.close)
                }
                .padding(12)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 28)
                .padding(.top, 18)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(viewModel.filteredWallpapers) { wallpaper in
                    MarketplaceWallpaperCard(
                        wallpaper: wallpaper,
                        folderPath: libraryViewModel.folderPath,
                        activeDownloadID: downloadManager.activeWallpaperID,
                        progress: downloadManager.progress,
                        onPreview: { previewWallpaper = wallpaper },
                        onPrimaryAction: { primaryAction(for: wallpaper) }
                    )
                }
            }
            .padding(28)

            VStack(spacing: 4) {
                Text("\(L.marketplaceSource) · \(viewModel.sourceDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L.marketplaceRightsNotice)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
    }

    private func primaryAction(for wallpaper: MarketplaceWallpaper) {
        let folderPath = libraryViewModel.folderPath
        if downloadManager.isDownloaded(wallpaper, folderPath: folderPath) {
            let localURL = downloadManager.localURL(for: wallpaper, folderPath: folderPath)
            let item = VideoItem(
                filename: localURL.lastPathComponent,
                path: localURL.path,
                thumbnailPath: "",
                kind: mediaKind(for: localURL),
                thumbnailSourcePath: ["jpg", "jpeg", "png", "gif"].contains(
                    localURL.pathExtension.lowercased()
                ) ? localURL.path : nil
            )
            libraryViewModel.startWallpaper(
                video: item,
                displays: Array(displayManager.selectedDisplays)
            )
            return
        }

        Task {
            guard await viewModel.download(wallpaper, folderPath: folderPath) != nil else {
                return
            }
            libraryViewModel.reloadContent()
        }
    }

    private func mediaKind(for url: URL) -> WallpaperMediaKind {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png": .image
        case "gif": .gif
        default: .video
        }
    }
}

private struct AddWallpaperSourceView: View {
    private enum SourceKind: String, CaseIterable, Identifiable {
        case github
        case manifest

        var id: String { rawValue }
    }

    @ObservedObject var viewModel: MarketplaceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var sourceKind: SourceKind = .github
    @State private var owner = ""
    @State private var repository = ""
    @State private var branch = "main"
    @State private var sourceName = ""
    @State private var manifestURL = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(L.addSource)
                    .font(.title2.bold())
                Spacer()
                Button(L.close) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Picker(L.sourceType, selection: $sourceKind) {
                Text(L.githubRepository).tag(SourceKind.github)
                Text(L.staticManifest).tag(SourceKind.manifest)
            }
            .pickerStyle(.segmented)

            Group {
                if sourceKind == .github {
                    TextField(L.owner, text: $owner)
                    TextField(L.repository, text: $repository)
                    TextField(L.branch, text: $branch)
                } else {
                    TextField(L.sourceName, text: $sourceName)
                    TextField(L.manifestURL, text: $manifestURL)
                }
            }
            .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button(L.add) {
                    do {
                        switch sourceKind {
                        case .github:
                            try viewModel.addGitHubProvider(
                                owner: owner,
                                repository: repository,
                                branch: branch
                            )
                        case .manifest:
                            try viewModel.addStaticManifestProvider(
                                name: sourceName,
                                urlString: manifestURL
                            )
                        }
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

private struct MarketplaceWallpaperCard: View {
    let wallpaper: MarketplaceWallpaper
    let folderPath: String
    let activeDownloadID: String?
    let progress: Double
    let onPreview: () -> Void
    let onPrimaryAction: () -> Void

    @ObservedObject private var downloadManager = WallpaperDownloadManager.shared
    @State private var isHovering = false

    private var isDownloaded: Bool {
        downloadManager.isDownloaded(wallpaper, folderPath: folderPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MarketplaceRemoteImage(url: wallpaper.thumbnailURL)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipped()
            .overlay(alignment: .topTrailing) {
                Text(wallpaper.resolution?.label ?? wallpaper.format)
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.62), in: Capsule())
                    .padding(10)
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(wallpaper.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(wallpaper.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if activeDownloadID == wallpaper.id {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }

                HStack(spacing: 8) {
                    Button(L.preview, action: onPreview)
                        .buttonStyle(.bordered)

                    Button(action: onPrimaryAction) {
                        Label(
                            isDownloaded ? L.applyWallpaperShort : L.download,
                            systemImage: isDownloaded ? "play.fill" : "arrow.down.circle"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(activeDownloadID != nil)
                }
            }
            .padding(13)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(isHovering ? 0.24 : 0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(isHovering ? 0.18 : 0.08), radius: 12, y: 6)
        .scaleEffect(isHovering ? 1.01 : 1)
        .onHover { isHovering = $0 }
    }
}

private struct MarketplacePreviewView: View {
    let wallpaper: MarketplaceWallpaper
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(wallpaper.title).font(.headline)
                    Text(wallpaper.detailText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L.close) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)

            if let imageURL = wallpaper.previewURL,
                ["jpg", "jpeg", "png", "gif"].contains(wallpaper.format.lowercased())
            {
                MarketplaceRemoteImage(url: imageURL)
                    .background(.black)
            } else if let player {
                VideoPlayer(player: player)
                    .background(.black)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 500)
        .onAppear {
            guard let previewURL = wallpaper.previewURL else { return }
            guard !["jpg", "jpeg", "png", "gif"].contains(
                wallpaper.format.lowercased()
            ) else { return }
            let player = AVPlayer(url: previewURL)
            player.isMuted = true
            self.player = player
            player.play()
        }
        .onDisappear {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
        }
    }
}

private struct MarketplaceRemoteImage: View {
    let url: URL?

    var body: some View {
        if let url, url.isFileURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Rectangle().fill(.quaternary)
                        .overlay { Image(systemName: "photo.badge.exclamationmark") }
                default:
                    Rectangle().fill(.quaternary)
                        .overlay { ProgressView().controlSize(.small) }
                }
            }
        }
    }
}
