import SwiftUI

struct TransferSheet: View {
    @Environment(PhoneLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Bindable var job: TransferJob

    var body: some View {
        VStack(spacing: 0) {
            switch job.phase {
            case .setup: setup
            case .copying, .deleting: running
            case .finished: finished
            }
        }
        .frame(width: 480)
        .interactiveDismissDisabled(job.phase == .copying || job.phase == .deleting)
    }

    // MARK: Setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: job.mode == .move ? "externaldrive.fill.badge.checkmark" : "doc.on.doc.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(job.mode.verb) \(Format.count(job.items.count, "item"))")
                        .font(.title2.weight(.semibold))
                    Text(Format.bytes(job.totalBytes))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Destination").font(.headline)
                HStack(spacing: 10) {
                    Image(systemName: "externaldrive")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        if let destination = job.destination {
                            Text(job.volumeName.map { "\($0) › \(destination.lastPathComponent)" } ?? destination.lastPathComponent)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(destination.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("No folder chosen").foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Choose…", action: chooseDestination)
                }
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

                if let available = job.availableSpace {
                    Label(
                        job.hasEnoughSpace
                            ? "\(Format.bytes(available)) available on this drive"
                            : "Not enough space: \(Format.bytes(available)) available, \(Format.bytes(job.totalBytes)) needed",
                        systemImage: job.hasEnoughSpace ? "checkmark.circle.fill" : "xmark.octagon.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(job.hasEnoughSpace ? .green : .red)
                }
                Text("Files are sorted into Photos, Screenshots and Videos folders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if job.mode == .move {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: library.iCloudPhotosEnabled ? "exclamationmark.triangle.fill" : "trash")
                        .foregroundStyle(library.iCloudPhotosEnabled ? .orange : .secondary)
                    Text(library.iCloudPhotosEnabled
                        ? "iCloud Photos is on, so your iPhone will refuse the delete step. The files will still be copied."
                        : "Each file is copied and its size checked against the original. Only files that check out are **deleted from your iPhone**, and they may not go to Recently Deleted.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(job.mode == .move ? "Move & Delete from iPhone" : "Copy") {
                    Task { await job.run(using: library) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(job.destination == nil || !job.hasEnoughSpace)
            }
        }
        .padding(24)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder on your hard drive for the photos and videos."
        panel.directoryURL = job.destination ?? URL(fileURLWithPath: "/Volumes")
        if panel.runModal() == .OK, let url = panel.url {
            job.destination = url
        }
    }

    // MARK: Running

    private var running: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(job.phase == .deleting ? "Removing from iPhone…" : "\(job.mode == .move ? "Moving" : "Copying") to \(job.volumeName ?? "drive")…")
                    .font(.title3.weight(.semibold))
            }

            if job.phase == .deleting {
                ProgressView().progressViewStyle(.linear)
                Text("Deleting \(Format.count(job.copiedCount, "verified item")) from your iPhone.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView(value: job.fractionComplete)
                    .progressViewStyle(.linear)
                    .animation(.linear(duration: 0.2), value: job.fractionComplete)
                HStack {
                    Text(job.currentName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text("\(job.processedCount) of \(job.items.count)")
                        .monospacedDigit()
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                Text("\(Format.bytes(job.copiedBytesEstimate)) of \(Format.bytes(job.totalBytes))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Text(job.wasStopped ? "Stopping after the current file…" : "Keep your iPhone unlocked and connected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Stop") { job.stop() }
                    .disabled(job.wasStopped || job.phase == .deleting)
            }
        }
        .padding(24)
    }

    // MARK: Finished

    private var finished: some View {
        VStack(spacing: 16) {
            let succeeded = job.failures.isEmpty && job.deleteError == nil && !job.wasStopped
            Image(systemName: succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(succeeded ? .green : .orange)
                .symbolEffect(.bounce, value: job.phase)

            VStack(spacing: 6) {
                Text(title).font(.title2.weight(.semibold))
                if job.mode == .move, job.freedBytes > 0 {
                    Text("Freed \(Format.bytes(job.freedBytes)) on your iPhone")
                        .font(.title3)
                        .foregroundStyle(.green)
                }
                if job.wasStopped {
                    Text("Stopped. Nothing was deleted from your iPhone.")
                        .foregroundStyle(.secondary)
                }
                if let deleteError = job.deleteError {
                    Text("Your iPhone refused to delete some items: \(deleteError)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            if !job.failures.isEmpty {
                DisclosureGroup("\(Format.count(job.failures.count, "item")) failed and \(job.mode == .move ? "were left on your iPhone" : "weren’t copied")") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(job.failures) { failure in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(failure.name).fontWeight(.medium)
                                    Text(failure.reason).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                }
                .font(.callout)
            }

            HStack {
                if let destination = job.destination {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([destination])
                    }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(24)
    }

    private var title: String {
        let copied = Format.count(job.copiedCount, "item")
        if job.mode == .move, job.deletedCount > 0 {
            return "Moved \(Format.count(job.deletedCount, "item"))"
        }
        return "Copied \(copied)"
    }
}
