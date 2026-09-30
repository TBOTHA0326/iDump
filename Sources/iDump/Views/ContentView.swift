import SwiftUI

struct ContentView: View {
    @Environment(PhoneLibrary.self) private var library

    @State private var category: Category = .all
    @State private var sizeFilter: SizeFilter = .any
    @State private var sort: ItemSort = .largest
    @State private var searchText = ""
    @State private var selection: Set<MediaItem.ID> = []
    @State private var selectionAnchor: MediaItem.ID?
    @State private var showInspector = true
    @State private var transfer: TransferJob?
    @AppStorage("tileSize") private var tileSize: Double = 150

    private var visibleItems: [MediaItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = library.items.filter { item in
            category.includes(item.kind)
                && item.size >= sizeFilter.minimumBytes
                && (query.isEmpty || item.name.localizedCaseInsensitiveContains(query))
        }
        return sort.sorted(filtered)
    }

    private var selectedItems: [MediaItem] {
        library.items.filter { selection.contains($0.id) }
    }

    var body: some View {
        let items = visibleItems

        NavigationSplitView {
            SidebarView(category: $category)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            detail(items)
                .navigationTitle(category.title)
                .navigationSubtitle(subtitle(for: items))
        }
        .inspector(isPresented: $showInspector) {
            InspectorView(items: selectedItems)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .toolbar { toolbar }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search file names")
        .sheet(item: $transfer) { job in
            TransferSheet(job: job)
        }
        .onChange(of: library.revision) {
            let ids = Set(library.items.map(\.id))
            selection.formIntersection(ids)
        }
    }

    // MARK: Detail

    @ViewBuilder
    private func detail(_ items: [MediaItem]) -> some View {
        switch library.status {
        case .searching:
            ContentUnavailableView {
                Label("Connect Your iPhone", systemImage: "cable.connector")
            } description: {
                Text("Plug your iPhone into this Mac with a cable, unlock it, and tap **Trust** if it asks.")
            }
        case .connecting:
            LoadingView(title: "Connecting to \(library.deviceName ?? "iPhone")…", percent: nil)
        case .locked:
            ContentUnavailableView {
                Label("Unlock Your iPhone", systemImage: "lock.iphone")
            } description: {
                Text("Unlock \(library.deviceName ?? "your iPhone") and tap **Trust This Computer** to see your photos and videos.")
            }
        case let .loading(percent):
            LoadingView(title: "Reading your library…", percent: percent)
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn’t Connect", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message + "\nTry unplugging and reconnecting your iPhone.")
            }
        case .ready:
            if items.isEmpty {
                emptyResults
            } else {
                MediaGridView(
                    items: items,
                    selection: $selection,
                    anchor: $selectionAnchor,
                    tileSize: tileSize
                )
                .safeAreaInset(edge: .top, spacing: 0) {
                    if library.iCloudPhotosEnabled { ICloudBanner() }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ActionBar(
                        visibleItems: items,
                        selectedItems: selectedItems,
                        onClear: { selection.removeAll() },
                        onTransfer: { mode in transfer = TransferJob(mode: mode, items: selectedItems) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var emptyResults: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if sizeFilter != .any {
            ContentUnavailableView {
                Label("Nothing \(sizeFilter.title.lowercased())", systemImage: "line.3.horizontal.decrease.circle")
            } actions: {
                Button("Show All Sizes") { sizeFilter = .any }
            }
        } else {
            ContentUnavailableView("No \(category.title)", systemImage: category.symbol)
        }
    }

    private func subtitle(for items: [MediaItem]) -> String {
        guard library.status == .ready else { return library.deviceName ?? "" }
        let bytes = items.reduce(Int64(0)) { $0 + $1.size }
        return "\(Format.count(items.count, "item")) · \(Format.bytes(bytes))"
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Size", selection: $sizeFilter) {
                    ForEach(SizeFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(
                    "Size Filter",
                    systemImage: sizeFilter == .any
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill"
                )
            }
            .help("Filter by file size")

            Menu {
                Picker("Sort By", selection: $sort) {
                    ForEach(ItemSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort order")

            Slider(value: $tileSize, in: 90...280) {
                Label("Thumbnail Size", systemImage: "square.grid.3x3")
            } minimumValueLabel: {
                Image(systemName: "square.grid.4x3.fill").imageScale(.small)
            } maximumValueLabel: {
                Image(systemName: "square.grid.2x2.fill").imageScale(.small)
            }
            .frame(width: 130)
            .help("Thumbnail size")

            Button {
                let visible = visibleItems
                if !visible.isEmpty && visible.allSatisfy({ selection.contains($0.id) }) {
                    selection.removeAll()
                } else {
                    selection = Set(visible.map(\.id))
                }
            } label: {
                Label("Select All", systemImage: "checkmark.circle")
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(library.status != .ready)
            .help("Select all (⌘A)")

            Button {
                showInspector.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help("Show or hide details")
        }
    }
}

// MARK: - Small supporting views

private struct LoadingView: View {
    let title: String
    let percent: Int?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse)
            Text(title).font(.title3.weight(.medium))
            if let percent {
                ProgressView(value: Double(percent), total: 100)
                    .frame(width: 240)
                Text("\(percent)%")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ICloudBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "icloud.fill").foregroundStyle(.blue)
            Text("iCloud Photos is on for this iPhone, so it won’t let a computer delete from it. You can still copy.")
                .font(.callout)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.blue.opacity(0.1))
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct ActionBar: View {
    let visibleItems: [MediaItem]
    let selectedItems: [MediaItem]
    let onClear: () -> Void
    let onTransfer: (TransferJob.Mode) -> Void

    var body: some View {
        HStack(spacing: 12) {
            if selectedItems.isEmpty {
                Text("Select items to copy or move them off your iPhone.")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("⌘-click to select several · ⇧-click for a range")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                let bytes = selectedItems.reduce(Int64(0)) { $0 + $1.size }
                Text("\(Format.count(selectedItems.count, "item")) selected")
                    .fontWeight(.medium)
                Text(Format.bytes(bytes))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Deselect", action: onClear)
                    .buttonStyle(.link)
                Spacer()
                Button {
                    onTransfer(.copy)
                } label: {
                    Label("Copy to Drive…", systemImage: "doc.on.doc")
                }
                .controlSize(.large)
                Button {
                    onTransfer(.move)
                } label: {
                    Label("Move to Drive…", systemImage: "externaldrive.fill.badge.checkmark")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
