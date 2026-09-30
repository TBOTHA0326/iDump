import AppKit
import ImageCaptureCore
import Observation

struct CategoryTotal {
    var count = 0
    var bytes: Int64 = 0
}

/// Finds the connected iPhone over USB (via ImageCaptureCore, the same framework
/// Image Capture uses) and exposes its photos and videos.
@Observable
final class PhoneLibrary: NSObject {
    enum Status: Equatable {
        case searching
        case connecting
        case locked
        case loading(percent: Int)
        case ready
        case failed(String)
    }

    private(set) var status: Status = .searching
    private(set) var deviceName: String?
    private(set) var items: [MediaItem] = []
    private(set) var totals: [Category: CategoryTotal] = [:]
    private(set) var kindTotals: [MediaKind: CategoryTotal] = [:]
    private(set) var revision = 0
    private(set) var iCloudPhotosEnabled = false

    @ObservationIgnored private let browser = ICDeviceBrowser()
    @ObservationIgnored private(set) var camera: ICCameraDevice?
    @ObservationIgnored private var rebuildScheduled = false
    @ObservationIgnored private var loadingTimer: Timer?

    func start() {
        guard !browser.isBrowsing else { return }
        browser.delegate = self
        let mask = ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: mask)!
        browser.start()
    }

    // MARK: Connection

    private func connect(_ camera: ICCameraDevice) {
        self.camera = camera
        camera.delegate = self
        deviceName = camera.name
        status = .connecting
        camera.requestOpenSession()
    }

    private func disconnect() {
        stopLoadingTimer()
        camera = nil
        deviceName = nil
        items = []
        totals = [:]
        kindTotals = [:]
        revision += 1
        status = .searching
        // Another camera-like device may still be attached.
        if let next = browser.devices?.compactMap({ $0 as? ICCameraDevice }).first {
            connect(next)
        }
    }

    private func beginLoading() {
        guard let camera else { return }
        status = .loading(percent: Int(camera.contentCatalogPercentCompleted))
        stopLoadingTimer()
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self, let camera = self.camera, case .loading = self.status else { return }
            self.status = .loading(percent: Int(camera.contentCatalogPercentCompleted))
        }
    }

    private func stopLoadingTimer() {
        loadingTimer?.invalidate()
        loadingTimer = nil
    }

    // MARK: Catalog

    private func scheduleRebuild() {
        guard !rebuildScheduled else { return }
        rebuildScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.rebuildScheduled = false
            self?.rebuild()
        }
    }

    private func rebuild() {
        guard let camera else { return }
        let files = (camera.mediaFiles ?? []).compactMap { $0 as? ICCameraFile }
        let built = MediaItem.build(from: files)

        var totals: [Category: CategoryTotal] = [:]
        var kindTotals: [MediaKind: CategoryTotal] = [:]
        for item in built {
            kindTotals[item.kind, default: .init()].count += 1
            kindTotals[item.kind, default: .init()].bytes += item.size
            for category in Category.allCases where category.includes(item.kind) {
                totals[category, default: .init()].count += 1
                totals[category, default: .init()].bytes += item.size
            }
        }

        items = built
        self.totals = totals
        self.kindTotals = kindTotals
        iCloudPhotosEnabled = camera.iCloudPhotosEnabled
        revision += 1
    }

    // MARK: File operations

    /// Copies a file off the phone. Returns the URL it was saved to.
    func download(
        _ file: ICCameraFile,
        to directory: URL,
        as filename: String,
        overwrite: Bool = false,
        progress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        var observation: NSKeyValueObservation?
        defer { observation?.invalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            let options: [ICDownloadOption: Any] = [
                .downloadsDirectoryURL: directory,
                .saveAsFilename: filename,
                .overwrite: overwrite,
            ]
            let request = file.requestDownload(options: options) { savedName, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: directory.appendingPathComponent(savedName ?? filename))
                }
            }
            if let progress, let request {
                observation = request.observe(\.fractionCompleted) { request, _ in
                    let fraction = request.fractionCompleted
                    DispatchQueue.main.async { progress(fraction) }
                }
            }
        }
    }

    /// Deletes files from the phone. Returns how many were actually deleted.
    func delete(_ files: [ICCameraFile]) async throws -> Int {
        guard let camera else { throw TransferError.phoneDisconnected }
        return try await withCheckedThrowingContinuation { continuation in
            camera.requestDeleteFiles(files, deleteFailed: { _ in }) { result, error in
                let deleted = result[.successful]?.count ?? 0
                if let error, deleted == 0 {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: deleted)
                }
            }
        }
    }

    /// Downloads a file to a temporary folder so it can be played or opened.
    func previewCopy(of file: ICCameraFile, progress: ((Double) -> Void)? = nil) async throws -> URL {
        let directory = Self.previewDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "\(file.ptpObjectHandle)-\(file.name ?? "file")"
        let url = directory.appendingPathComponent(filename)
        if let size = FileManager.default.fileSize(at: url), size == Int64(file.fileSize) {
            return url
        }
        return try await download(file, to: directory, as: filename, overwrite: true, progress: progress)
    }

    static let previewDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("iDump Previews", isDirectory: true)

    static func clearPreviews() {
        try? FileManager.default.removeItem(at: previewDirectory)
    }
}

enum TransferError: LocalizedError {
    case phoneDisconnected
    case verificationFailed(expected: Int64, actual: Int64)

    var errorDescription: String? {
        switch self {
        case .phoneDisconnected:
            "The iPhone was disconnected."
        case let .verificationFailed(expected, actual):
            "Copy didn’t match the original (\(Format.bytes(actual)) of \(Format.bytes(expected)))."
        }
    }
}

extension FileManager {
    func fileSize(at url: URL) -> Int64? {
        (try? attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }
}

// MARK: - ICDeviceBrowserDelegate

extension PhoneLibrary: ICDeviceBrowserDelegate {
    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let camera = device as? ICCameraDevice else { return }
        if self.camera == nil { connect(camera) }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        if device == camera { disconnect() }
    }
}

// MARK: - ICCameraDeviceDelegate

extension PhoneLibrary: ICCameraDeviceDelegate {
    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        guard let camera = device as? ICCameraDevice, camera == self.camera else { return }
        if camera.isAccessRestrictedAppleDevice {
            status = .locked
        } else if let error {
            status = .failed(error.localizedDescription)
        } else {
            // Show the real HEIC/HEVC originals, i.e. what actually uses space on the phone.
            camera.mediaPresentation = .originalAssets
            iCloudPhotosEnabled = camera.iCloudPhotosEnabled
            beginLoading()
        }
    }

    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        guard device == camera else { return }
        stopLoadingTimer()
        status = .ready
        rebuild()
    }

    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        if status == .ready { scheduleRebuild() }
    }

    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
        if status == .ready { scheduleRebuild() }
    }

    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        guard device == camera, status == .locked else { return }
        beginLoading()
    }

    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        guard device == camera else { return }
        stopLoadingTimer()
        status = .locked
    }

    func didRemove(_ device: ICDevice) {
        if device == camera { disconnect() }
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}
    func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}
    func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}
    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
}
