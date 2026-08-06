import Foundation
import Observation
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class BackupViewModel {
    var selectedPhotos: [PhotosPickerItem] = []
    var uploadProgress: Float = 0
    var currentUploadIndex = 0
    var totalUploads = 0
    var phase: LoadingPhase<Void> = .idle
    var storageInfo: ServerStorageDTO?
    var failedUploads: [String] = []
    var successCount = 0
    var skippedCount = 0

    private let repo: BackupRepository
    private let dataManager: SwiftDataManager?

    init(repo: BackupRepository, dataManager: SwiftDataManager? = nil) {
        self.repo = repo
        self.dataManager = dataManager
    }

    func loadStorageInfo() async {
        do {
            storageInfo = try await repo.getStorageInfo()
        } catch {
            storageInfo = nil
        }
    }

    /// Kembali ke layar pemilihan foto setelah ringkasan/error.
    func reset() {
        phase = .idle
        uploadProgress = 0
        currentUploadIndex = 0
        totalUploads = 0
    }

    func uploadSelectedPhotos() async {
        guard !selectedPhotos.isEmpty else { return }

        phase = .loading
        totalUploads = selectedPhotos.count
        currentUploadIndex = 0
        uploadProgress = 0
        failedUploads = []
        successCount = 0
        skippedCount = 0

        // Muat data + checksum dulu supaya duplikat bisa dicek dalam satu request.
        var prepared: [(index: Int, data: Data, checksum: String, filename: String)] = []
        for (index, item) in selectedPhotos.enumerated() {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let checksum = await repo.checksum(for: data)
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                prepared.append((index, data, checksum, "\(checksum.prefix(12)).\(ext)"))
            } else {
                failedUploads.append("Item \(index + 1)")
            }
        }

        // Duplikat menurut server (berdasarkan checksum) — dilewati, bukan diunggah ulang.
        var duplicates: Set<String> = []
        if let result = try? await repo.checkDuplicates(prepared.map { (id: $0.checksum, checksum: $0.checksum) }) {
            duplicates = result
        }

        for entry in prepared {
            do {
                if duplicates.contains(entry.checksum) || dataManager?.getBackupRecord(deviceAssetId: entry.checksum) != nil {
                    skippedCount += 1
                } else {
                    let now = Date()
                    let assetId = try await repo.uploadAsset(
                        data: entry.data,
                        filename: entry.filename,
                        checksum: entry.checksum,
                        createdAt: now,
                        modifiedAt: now
                    )
                    try? dataManager?.insertBackupRecord(BackupRecord(
                        id: UUID().uuidString,
                        assetId: assetId,
                        deviceAssetId: entry.checksum
                    ))
                    successCount += 1
                }
            } catch {
                failedUploads.append("Item \(entry.index + 1)")
            }
            currentUploadIndex += 1
            uploadProgress = totalUploads > 0 ? Float(currentUploadIndex) / Float(totalUploads) : 0
        }

        selectedPhotos = []
        phase = .loaded(())
    }
}
