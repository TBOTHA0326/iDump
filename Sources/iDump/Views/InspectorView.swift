import AVKit
import SwiftUI

struct InspectorView: View {
    let items: [MediaItem]

    var body: some View {
        Group {
            if items.count == 1, let item = items.first {
                SingleItemInspector(item: item).id(item.id)
            } else if items.count > 1 {
                MultiItemInspector(items: items)
            } else {
                ContentUnavailableView {
                    Label("No Selection", systemImage: "square.dashed")
                } description: {
                    Text("Select a photo or video to preview it.\n\nTip: sort by **Largest First** to find what’s eating your storage.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Single item

private struct SingleItemInspector: View {
    @Environment(PhoneLibrary.self) private var library
    let item: MediaItem

    @State private var preview: NSImage?
    @State private var player: AVPlayer?
    @State private var downloadProgress: Double?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                previewArea

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    Label(item.isLivePhoto ? "Live Photo" : item.kind.singularTitle, systemImage: item.isLivePhoto ? "livephoto" : item.kind.symbol)
                        .font(.callout)
                        .foregroundStyle(item.kind.tint)
                }

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                    InfoRow(label: "Size", value: Format.bytes(item.size))
                    if item.isLivePhoto {
                        InfoRow(label: "", value: "Includes the Live Photo video", secondary: true)
                    }
                    if item.pixelWidth > 0 {
                        InfoRow(label: "Dimensions", value: "\(item.pixelWidth) × \(item.pixelHeight)")
                    }
                    if item.kind == .video {
                        InfoRow(label: "Duration", value: Format.duration(item.duration))
                    }
                    if let date = item.date {
                        InfoRow(label: "Taken", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                    if !item.folder.isEmpty {
                        InfoRow(label: "Folder", value: item.folder)
                    }
                }
                .font(.callout)

                Button {
                    Task { await openOriginal() }
                } label: {
                    Label("Open Original", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(downloadProgress != nil)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
        .task {
            preview = ThumbnailCache.shared.cached(for: item, maxPixel: 320)
            if let large = await ThumbnailCache.shared.thumbnail(for: item, maxPixel: 1200) {
                preview = large
            }
        }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private var previewArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)

            if let player {
                VideoPlayer(player: player)
            } else if let preview {
                Image(nsImage: preview)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView().controlSize(.small)
            }

            if item.kind == .video, player == nil {
                if let downloadProgress {
                    VStack(spacing: 8) {
                        ProgressView(value: downloadProgress)
                            .progressViewStyle(.circular)
                        Text("Loading video…").font(.caption)
                    }
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Button {
                        Task { await loadVideo() }
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 52))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.45))
                            .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                    .help("Play video (copies it to a temporary folder first)")
                }
            }
        }
        .aspectRatio(previewAspect, contentMode: .fit)
        .frame(maxHeight: 420)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(maxWidth: .infinity)
    }

    private var previewAspect: CGFloat {
        if let preview, preview.size.height > 0 { return preview.size.width / preview.size.height }
        return 1
    }

    private func fetchPreviewCopy() async -> URL? {
        errorMessage = nil
        downloadProgress = 0
        defer { downloadProgress = nil }
        do {
            return try await library.previewCopy(of: item.file) { downloadProgress = $0 }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func loadVideo() async {
        guard let url = await fetchPreviewCopy() else { return }
        let player = AVPlayer(url: url)
        self.player = player
        player.play()
    }

    private func openOriginal() async {
        guard let url = await fetchPreviewCopy() else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var secondary = false

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .foregroundStyle(secondary ? .secondary : .primary)
                .font(secondary ? .caption : nil)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Multiple items

private struct MultiItemInspector: View {
    let items: [MediaItem]

    var body: some View {
        let totalBytes = items.reduce(Int64(0)) { $0 + $1.size }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ThumbnailStack(items: Array(items.prefix(3)))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(items.count.formatted()) Items Selected")
                        .font(.title3.weight(.semibold))
                    Text(Format.bytes(totalBytes))
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.tint)
                    Text("will be freed if you move these off your iPhone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 8) {
                    ForEach(MediaKind.allCases, id: \.self) { kind in
                        let subset = items.filter { $0.kind == kind }
                        if !subset.isEmpty {
                            HStack {
                                Label(kind.title, systemImage: kind.symbol)
                                    .foregroundStyle(kind.tint)
                                Text("\(subset.count)")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Format.bytes(subset.reduce(0) { $0 + $1.size }))
                                    .monospacedDigit()
                            }
                            .font(.callout)
                        }
                    }
                }
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(16)
        }
    }
}

private struct ThumbnailStack: View {
    let items: [MediaItem]

    var body: some View {
        ZStack {
            ForEach(Array(items.enumerated().reversed()), id: \.element.id) { index, item in
                StackCard(item: item)
                    .rotationEffect(.degrees(Double(index) * 6 - 6))
                    .offset(x: CGFloat(index) * 10 - 10)
            }
        }
        .frame(height: 150)
    }
}

private struct StackCard: View {
    let item: MediaItem
    @State private var image: NSImage?

    var body: some View {
        Color.clear
            .frame(width: 120, height: 120)
            .background(.quaternary)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
            .task(id: item.id) {
                image = await ThumbnailCache.shared.thumbnail(for: item, maxPixel: 320)
            }
    }
}
