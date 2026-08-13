import Combine
import Foundation
import UniformTypeIdentifiers
import UIKit

struct SharePreviewItem: Identifiable {
    var uploadItem: SharedUploadItem
    let fileURL: URL
    let thumbnail: UIImage?
    var isSelected = true

    var id: UUID { uploadItem.id }
}

@MainActor
final class ShareExtensionModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case ready
        case uploading(current: Int, total: Int)
        case queued(Int)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var items: [SharePreviewItem] = []
    @Published private(set) var session = SharedSessionStore.load()
    private let batchID = UUID()
    private weak var shareContext: NSExtensionContext?
    private var hasLoaded = false

    init(extensionContext: NSExtensionContext?) {
        shareContext = extensionContext
    }

    var selectedCount: Int { items.count(where: \.isSelected) }
    var isBusy: Bool {
        if case .uploading = phase { return true }
        return phase == .loading
    }
    var serverLabel: String {
        session?.displayServerURL ?? String(localized: "Sign in to SelfPhotos first")
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        do {
            let directory = try await SharedUploadStore.shared.makeBatchDirectory(id: batchID)
            let providers = (shareContext?.inputItems as? [NSExtensionItem] ?? [])
                .flatMap { $0.attachments ?? [] }
                .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
                .prefix(30)

            for provider in providers {
                let materialized = try await Self.materialize(
                    provider: provider,
                    directory: directory)
                items.append(materialized)
            }

            phase = items.isEmpty
                ? .failed(String(localized: "No supported images were shared."))
                : .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func toggle(_ id: UUID) {
        guard !isBusy, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isSelected.toggle()
    }

    func primaryAction() {
        switch phase {
        case .queued:
            complete()
        case .ready, .failed:
            Task { await uploadSelected() }
        default:
            break
        }
    }

    func cancel() {
        Task {
            try? await SharedUploadStore.shared.removeBatch(id: batchID)
            shareContext?.completeRequest(returningItems: nil)
        }
    }

    private func uploadSelected() async {
        guard let credential = session?.credential() else {
            phase = .failed(String(localized: "Open SelfPhotos and sign in before uploading."))
            return
        }

        let selected = items.filter(\.isSelected)
        guard !selected.isEmpty else { return }

        var batch = SharedUploadBatch(
            id: batchID,
            owner: credential.owner,
            createdAt: .now,
            items: selected.map(\.uploadItem))

        do {
            try await SharedUploadStore.shared.save(batch)
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        let client = SharedUploadClient(credential: credential)
        var queued = 0
        for index in batch.items.indices {
            phase = .uploading(current: index + 1, total: batch.items.count)
            batch.items[index].state = .uploading
            batch.items[index].lastError = nil
            try? await SharedUploadStore.shared.save(batch)

            do {
                let item = batch.items[index]
                let fileURL = try await SharedUploadStore.shared.fileURL(
                    for: item,
                    batchID: batch.id)
                let directory = try await SharedUploadStore.shared.makeBatchDirectory(id: batch.id)
                _ = try await client.upload(
                    item: item,
                    fileURL: fileURL,
                    bodyDirectory: directory)
                batch.items[index].state = .uploaded
                try? await SharedUploadStore.shared.removeFile(for: item, batchID: batch.id)
            } catch {
                queued += 1
                batch.items[index].state = .queued
                batch.items[index].lastError = error.localizedDescription
            }
            try? await SharedUploadStore.shared.save(batch)
        }

        batch.items.removeAll { $0.state == .uploaded }
        if batch.items.isEmpty {
            try? await SharedUploadStore.shared.removeBatch(id: batch.id)
            phase = .queued(0)
            try? await Task.sleep(for: .milliseconds(450))
            complete()
        } else {
            try? await SharedUploadStore.shared.save(batch)
            phase = .queued(queued)
        }
    }

    private func complete() {
        shareContext?.completeRequest(returningItems: nil)
    }

    private nonisolated static func materialize(
        provider: NSItemProvider,
        directory: URL
    ) async throws -> SharePreviewItem {
        let providerSuggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<SharePreviewItem, Error>) in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) {
                sourceURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sourceURL else {
                    continuation.resume(throwing: SharedUploadStoreError.invalidFilename)
                    return
                }

                do {
                    let type = UTType(filenameExtension: sourceURL.pathExtension) ?? .image
                    let fallbackExtension = type.preferredFilenameExtension ?? "jpg"
                    var suggested = providerSuggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if suggested?.isEmpty != false { suggested = sourceURL.deletingPathExtension().lastPathComponent }
                    if (suggested as NSString?)?.pathExtension.isEmpty != false {
                        suggested = "\(suggested ?? "Shared Image").\(fallbackExtension)"
                    }
                    let safeName = sanitize(suggested ?? "Shared Image.\(fallbackExtension)")
                    let id = UUID()
                    let storedName = "\(id.uuidString)-\(safeName)"
                    let destination = directory.appendingPathComponent(storedName)
                    try FileManager.default.copyItem(at: sourceURL, to: destination)

                    let values = try destination.resourceValues(forKeys: [
                        .fileSizeKey,
                        .creationDateKey,
                        .contentModificationDateKey,
                    ])
                    let now = Date()
                    let item = SharedUploadItem(
                        id: id,
                        filename: safeName,
                        relativePath: storedName,
                        contentType: type.preferredMIMEType ?? "application/octet-stream",
                        byteCount: Int64(values.fileSize ?? 0),
                        createdAt: values.creationDate ?? now,
                        modifiedAt: values.contentModificationDate ?? now,
                        state: .queued,
                        lastError: nil)
                    continuation.resume(returning: SharePreviewItem(
                        uploadItem: item,
                        fileURL: destination,
                        thumbnail: UIImage(contentsOfFile: destination.path)))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated static func sanitize(_ filename: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\")
        let pieces = filename.components(separatedBy: forbidden)
        let joined = pieces.filter { !$0.isEmpty }.joined(separator: "-")
        return joined.isEmpty ? "Shared Image.jpg" : joined
    }
}
