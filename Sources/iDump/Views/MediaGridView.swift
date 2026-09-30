import SwiftUI

struct MediaGridView: View {
    let items: [MediaItem]
    @Binding var selection: Set<MediaItem.ID>
    @Binding var anchor: MediaItem.ID?
    let tileSize: Double

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: tileSize, maximum: tileSize * 1.5), spacing: 12)],
                spacing: 12
            ) {
                ForEach(items) { item in
                    ThumbnailCell(item: item, isSelected: selection.contains(item.id), pixelSize: tileSize > 180 ? 480 : 320)
                        .onTapGesture { handleClick(on: item) }
                }
            }
            .padding(16)
        }
        .background {
            // Clicking empty space clears the selection, like Finder.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { selection.removeAll() }
        }
    }

    private func handleClick(on item: MediaItem) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift), let anchor,
           let from = items.firstIndex(where: { $0.id == anchor }),
           let to = items.firstIndex(where: { $0.id == item.id }) {
            let range = min(from, to)...max(from, to)
            selection.formUnion(items[range].map(\.id))
        } else if modifiers.contains(.command) {
            if selection.contains(item.id) {
                selection.remove(item.id)
            } else {
                selection.insert(item.id)
            }
            anchor = item.id
        } else {
            selection = [item.id]
            anchor = item.id
        }
    }
}

struct ThumbnailCell: View {
    let item: MediaItem
    let isSelected: Bool
    let pixelSize: Int

    @State private var image: NSImage?
    @State private var isHovering = false

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(.quaternary)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    Image(systemName: item.kind.symbol)
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .bottom) { bottomBadges }
            .overlay(alignment: .topLeading) {
                if item.isLivePhoto {
                    Image(systemName: "livephoto")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(7)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .shadow(radius: 2)
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            }
            .scaleEffect(isHovering && !isSelected ? 1.02 : 1)
            .shadow(color: .black.opacity(isHovering ? 0.18 : 0), radius: 6, y: 3)
            .animation(.snappy(duration: 0.15), value: isHovering)
            .animation(.snappy(duration: 0.15), value: isSelected)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .help("\(item.name) · \(Format.bytes(item.size))")
            .task(id: item.id) {
                if let cached = ThumbnailCache.shared.cached(for: item, maxPixel: pixelSize) {
                    image = cached
                    return
                }
                // Short delay so fast scrolling doesn't queue thousands of requests on the phone.
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                let loaded = await ThumbnailCache.shared.thumbnail(for: item, maxPixel: pixelSize)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
    }

    private var bottomBadges: some View {
        HStack(spacing: 4) {
            Badge(text: Format.bytes(item.size), emphasized: item.size >= 100_000_000)
            Spacer(minLength: 0)
            if item.kind == .video {
                Badge(text: Format.duration(item.duration), symbol: "play.fill")
            }
        }
        .padding(6)
    }
}

private struct Badge: View {
    let text: String
    var symbol: String?
    var emphasized = false

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 8)) }
            Text(text)
        }
        .font(.system(size: 10.5, weight: emphasized ? .bold : .semibold).monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(emphasized ? AnyShapeStyle(Color.orange.opacity(0.9)) : AnyShapeStyle(.black.opacity(0.55)), in: Capsule())
        .lineLimit(1)
    }
}
