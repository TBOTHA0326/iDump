import Foundation
import ImageCaptureCore
import UniformTypeIdentifiers

enum MediaKind: String, CaseIterable {
    case photo, screenshot, video

    var title: String {
        switch self {
        case .photo: "Photos"
        case .screenshot: "Screenshots"
        case .video: "Videos"
        }
    }

    var singularTitle: String {
        switch self {
        case .photo: "Photo"
        case .screenshot: "Screenshot"
        case .video: "Video"
        }
    }

    var symbol: String {
        switch self {
        case .photo: "photo"
        case .screenshot: "camera.viewfinder"
        case .video: "video.fill"
        }
    }
}

/// One thing the user sees in the grid. A Live Photo is a single item made of
/// the still image plus its short companion movie.
final class MediaItem: Identifiable, Hashable {
    let id: ObjectIdentifier
    let file: ICCameraFile
    let companions: [ICCameraFile]
    let kind: MediaKind
    let name: String
    let folder: String
    let size: Int64
    let date: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: Double

    var isLivePhoto: Bool { !companions.isEmpty }
    var allFiles: [ICCameraFile] { [file] + companions }

    init(file: ICCameraFile, companions: [ICCameraFile], kind: MediaKind) {
        self.id = ObjectIdentifier(file)
        self.file = file
        self.companions = companions
        self.kind = kind
        self.name = file.name ?? "Untitled"
        self.folder = file.parentFolder?.name ?? ""
        self.size = ([file] + companions).reduce(0) { $0 + Int64($1.fileSize) }
        self.date = file.exifCreationDate ?? file.creationDate ?? file.fileCreationDate
        self.pixelWidth = file.width
        self.pixelHeight = file.height
        self.duration = file.duration
    }

    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Building items from the device catalog

extension MediaItem {
    static func build(from files: [ICCameraFile]) -> [MediaItem] {
        var stills: [ICCameraFile] = []
        var movies: [ICCameraFile] = []
        for file in files {
            if isMovie(file) { movies.append(file) } else if !isAudio(file) { stills.append(file) }
        }

        var stillByGroup: [String: ICCameraFile] = [:]
        var stillByName: [String: ICCameraFile] = [:]
        for still in stills {
            if let group = still.groupUUID, !group.isEmpty { stillByGroup[group] = still }
            stillByName[baseKey(still)] = still
        }

        // Live Photo movies share a group UUID (or base filename) with their still.
        var companions: [ObjectIdentifier: [ICCameraFile]] = [:]
        var standaloneMovies: [ICCameraFile] = []
        for movie in movies {
            var owner: ICCameraFile?
            if let group = movie.groupUUID, !group.isEmpty { owner = stillByGroup[group] }
            if owner == nil, movie.duration <= 4, let still = stillByName[baseKey(movie)] { owner = still }
            if let owner {
                companions[ObjectIdentifier(owner), default: []].append(movie)
            } else {
                standaloneMovies.append(movie)
            }
        }

        var items: [MediaItem] = []
        items.reserveCapacity(stills.count + standaloneMovies.count)
        for still in stills {
            let kind: MediaKind = isScreenshot(still) ? .screenshot : .photo
            items.append(MediaItem(file: still, companions: companions[ObjectIdentifier(still)] ?? [], kind: kind))
        }
        for movie in standaloneMovies {
            items.append(MediaItem(file: movie, companions: [], kind: .video))
        }
        return items
    }

    private static func baseKey(_ file: ICCameraFile) -> String {
        let name = ((file.name ?? "") as NSString).deletingPathExtension.uppercased()
        return "\(file.parentFolder?.name ?? "")/\(name)"
    }

    private static func fileType(_ file: ICCameraFile) -> UTType? {
        if let uti = file.uti, let type = UTType(uti) { return type }
        let ext = ((file.name ?? "") as NSString).pathExtension
        return UTType(filenameExtension: ext)
    }

    private static func isMovie(_ file: ICCameraFile) -> Bool {
        fileType(file)?.conforms(to: .movie) ?? false
    }

    private static func isAudio(_ file: ICCameraFile) -> Bool {
        guard let type = fileType(file) else { return false }
        return type.conforms(to: .audio) && !type.conforms(to: .movie)
    }

    /// iPhone screenshots are PNGs at the exact screen resolution. The camera
    /// never writes PNGs, and never shoots at a screen resolution.
    private static let screenResolutions: Set<String> = [
        "640x1136", "750x1334", "828x1792", "1080x1920", "1125x2436", "1170x2532",
        "1179x2556", "1206x2622", "1242x2208", "1242x2688", "1260x2736", "1284x2778",
        "1290x2796", "1320x2868", "1080x2340",
    ]

    private static func isScreenshot(_ file: ICCameraFile) -> Bool {
        let ext = ((file.name ?? "") as NSString).pathExtension.lowercased()
        if ext == "png" { return true }
        let short = min(file.width, file.height), long = max(file.width, file.height)
        return ext != "heic" && screenResolutions.contains("\(short)x\(long)")
    }
}

// MARK: - Filtering & sorting

enum Category: String, CaseIterable, Identifiable {
    case all, photos, screenshots, videos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Items"
        case .photos: "Photos"
        case .screenshots: "Screenshots"
        case .videos: "Videos"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .photos: "photo.on.rectangle"
        case .screenshots: "camera.viewfinder"
        case .videos: "video"
        }
    }

    func includes(_ kind: MediaKind) -> Bool {
        switch self {
        case .all: true
        case .photos: kind == .photo
        case .screenshots: kind == .screenshot
        case .videos: kind == .video
        }
    }
}

enum SizeFilter: Int, CaseIterable, Identifiable {
    case any = 0, over1MB = 1, over10MB = 10, over50MB = 50, over100MB = 100, over500MB = 500, over1GB = 1000

    var id: Int { rawValue }
    var minimumBytes: Int64 { Int64(rawValue) * 1_000_000 }

    var title: String {
        switch self {
        case .any: "Any Size"
        case .over1GB: "Larger than 1 GB"
        default: "Larger than \(rawValue) MB"
        }
    }
}

enum ItemSort: String, CaseIterable, Identifiable {
    case largest, smallest, newest, oldest, name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .largest: "Largest First"
        case .smallest: "Smallest First"
        case .newest: "Newest First"
        case .oldest: "Oldest First"
        case .name: "Name"
        }
    }

    func sorted(_ items: [MediaItem]) -> [MediaItem] {
        switch self {
        case .largest: items.sorted { $0.size > $1.size }
        case .smallest: items.sorted { $0.size < $1.size }
        case .newest: items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        case .oldest: items.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        case .name: items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}

// MARK: - Formatting

enum Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func count(_ value: Int, _ noun: String) -> String {
        "\(value.formatted()) \(noun)\(value == 1 ? "" : "s")"
    }
}
