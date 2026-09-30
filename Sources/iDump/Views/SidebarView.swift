import SwiftUI

extension MediaKind {
    var tint: Color {
        switch self {
        case .photo: .blue
        case .screenshot: .purple
        case .video: .orange
        }
    }
}

extension Category {
    var tint: Color {
        switch self {
        case .all: .accentColor
        case .photos: MediaKind.photo.tint
        case .screenshots: MediaKind.screenshot.tint
        case .videos: MediaKind.video.tint
        }
    }
}

struct SidebarView: View {
    @Environment(PhoneLibrary.self) private var library
    @Binding var category: Category

    var body: some View {
        List(selection: $category) {
            Section("Library") {
                ForEach(Category.allCases) { category in
                    let total = library.totals[category] ?? .init()
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(category.title)
                                if library.status == .ready {
                                    Text(Format.count(total.count, "item"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: category.symbol)
                                .foregroundStyle(category.tint)
                        }
                        Spacer()
                        if library.status == .ready {
                            Text(Format.bytes(total.bytes))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(category)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            DeviceCard()
                .padding(10)
        }
    }
}

private struct DeviceCard: View {
    @Environment(PhoneLibrary.self) private var library

    private var statusText: String {
        switch library.status {
        case .searching: "Not connected"
        case .connecting: "Connecting…"
        case .locked: "Locked. Unlock to continue"
        case let .loading(percent): "Reading library… \(percent)%"
        case .ready: "Connected via USB"
        case .failed: "Connection problem"
        }
    }

    private var statusColor: Color {
        switch library.status {
        case .ready: .green
        case .searching, .failed: .secondary
        default: .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 22, weight: .light))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(library.deviceName ?? "No iPhone")
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(statusColor).frame(width: 6, height: 6)
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if library.status == .ready, let all = library.totals[.all], all.bytes > 0 {
                UsageBar(totals: library.kindTotals, totalBytes: all.bytes)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(MediaKind.allCases, id: \.self) { kind in
                        HStack(spacing: 6) {
                            Circle().fill(kind.tint).frame(width: 7, height: 7)
                            Text(kind.title)
                            Spacer()
                            Text(Format.bytes(library.kindTotals[kind]?.bytes ?? 0))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                    Divider().padding(.vertical, 2)
                    HStack {
                        Text("Total").fontWeight(.semibold)
                        Spacer()
                        Text(Format.bytes(all.bytes)).fontWeight(.semibold).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }
        .padding(12)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }
}

private struct UsageBar: View {
    let totals: [MediaKind: CategoryTotal]
    let totalBytes: Int64

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1.5) {
                ForEach(MediaKind.allCases, id: \.self) { kind in
                    let bytes = totals[kind]?.bytes ?? 0
                    if bytes > 0 {
                        Rectangle()
                            .fill(kind.tint.gradient)
                            .frame(width: max(2, proxy.size.width * CGFloat(bytes) / CGFloat(totalBytes)))
                    }
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }
}
