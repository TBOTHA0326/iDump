import Foundation
import ImageCaptureCore
import Observation

/// Copies items to a folder, verifies each copy byte-for-byte in size, and (in
/// move mode) deletes from the iPhone only the items whose copies verified.
@MainActor
@Observable
final class TransferJob: Identifiable {
    enum Mode {
        case copy, move

        var verb: String { self == .copy ? "Copy" : "Move" }
    }

    enum Phase {
        case setup, copying, deleting, finished
    }

    struct Failure: Identifiable {
        let id = UUID()
        let name: String
        let reason: String
    }

    let id = UUID()
    let mode: Mode
    let items: [MediaItem]
    let totalBytes: Int64

    var destination: URL? {
        didSet { UserDefaults.standard.set(destination?.path, forKey: Self.destinationKey) }
    }

    private(set) var phase: Phase = .setup
    private(set) var currentName = ""
    private(set) var processedCount = 0
    private(set) var copiedCount = 0
    private(set) var deletedCount = 0
    private(set) var freedBytes: Int64 = 0
    private(set) var failures: [Failure] = []
    private(set) var wasStopped = false
    private(set) var deleteError: String?
    private var processedBytes: Int64 = 0
    private var currentFileBytes: Int64 = 0
    private var currentFileFraction: Double = 0

    private static let destinationKey = "destinationPath"

    init(mode: Mode, items: [MediaItem]) {
        self.mode = mode
        self.items = items
        self.totalBytes = items.reduce(0) { $0 + $1.size }
        if let path = UserDefaults.standard.string(forKey: Self.destinationKey),
           FileManager.default.fileExists(atPath: path) {
            destination = URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    var fractionComplete: Double {
        guard totalBytes > 0 else { return 0 }
        let done = Double(processedBytes) + currentFileFraction * Double(currentFileBytes)
        return min(1, done / Double(totalBytes))
    }

    var copiedBytesEstimate: Int64 { Int64(fractionComplete * Double(totalBytes)) }

    var availableSpace: Int64? {
        guard let destination,
              let values = try? destination.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let capacity = values.volumeAvailableCapacity else { return nil }
        return Int64(capacity)
    }

    var volumeName: String? {
        (try? destination?.resourceValues(forKeys: [.volumeNameKey]))?.volumeName
    }

    var hasEnoughSpace: Bool {
        guard let availableSpace else { return true }
        return availableSpace > totalBytes
    }

    func stop() { wasStopped = true }

    func run(using library: PhoneLibrary) async {
        guard let destination else { return }
        phase = .copying
        var verified: [MediaItem] = []

        for item in items {
            if wasStopped { break }
            currentName = item.name
            do {
                for file in item.allFiles {
                    try await copy(file, of: item, into: destination, library: library)
                }
                verified.append(item)
                copiedCount += 1
            } catch {
                failures.append(Failure(name: item.name, reason: error.localizedDescription))
            }
            processedBytes += item.size
            currentFileBytes = 0
            currentFileFraction = 0
            processedCount += 1
        }

        // Stopping means "don't touch my phone": nothing gets deleted.
        if mode == .move, !wasStopped, !verified.isEmpty {
            phase = .deleting
            let batchSize = 50
            for start in stride(from: 0, to: verified.count, by: batchSize) {
                let batch = Array(verified[start..<min(start + batchSize, verified.count)])
                do {
                    _ = try await library.delete(batch.flatMap(\.allFiles))
                    deletedCount += batch.count
                    freedBytes += batch.reduce(0) { $0 + $1.size }
                } catch {
                    deleteError = error.localizedDescription
                    break
                }
            }
        }
        phase = .finished
    }

    private func copy(_ file: ICCameraFile, of item: MediaItem, into root: URL, library: PhoneLibrary) async throws {
        let fm = FileManager.default
        let folder = root.appendingPathComponent(item.kind.title, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let expected = Int64(file.fileSize)
        let name = file.name ?? "Untitled"
        var target = folder.appendingPathComponent(name)
        if fm.fileExists(atPath: target.path) {
            // Already copied on an earlier run: accept it as verified.
            if fm.fileSize(at: target) == expected { return }
            target = uniqueURL(for: target)
        }

        currentFileBytes = expected
        currentFileFraction = 0
        let saved = try await library.download(file, to: folder, as: target.lastPathComponent) { [weak self] fraction in
            self?.currentFileFraction = fraction
        }

        let actual = fm.fileSize(at: saved) ?? -1
        guard actual == expected else {
            throw TransferError.verificationFailed(expected: expected, actual: max(actual, 0))
        }
        if let date = item.date {
            try? fm.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: saved.path)
        }
    }

    private func uniqueURL(for url: URL) -> URL {
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let folder = url.deletingLastPathComponent()
        var index = 2
        while true {
            let candidate = folder.appendingPathComponent("\(base) \(index)").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }
}
