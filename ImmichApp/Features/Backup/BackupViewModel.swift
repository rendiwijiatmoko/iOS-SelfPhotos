import Foundation
import Observation
import SwiftUI
import PhotosUI

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

    private let repo: BackupRepository

    init(repo: BackupRepository) {
        self.repo = repo
    }

    func loadStorageInfo() async {
        do {
            storageInfo = try await repo.getStorageInfo()
        } catch {
            // Handle silently
        }
    }

    func uploadSelectedPhotos() async {
        guard !selectedPhotos.isEmpty else { return }

        phase = .loading
        totalUploads = selectedPhotos.count
        currentUploadIndex = 0
        failedUploads = []
        successCount = 0

        for (index, item) in selectedPhotos.enumerated() {
            currentUploadIndex = index + 1
            updateProgress()

            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("jpg")

                    try data.write(to: tempURL)

                    let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
                    let now = Date()

                    _ = try await repo.uploadAsset(
                        fileURL: tempURL,
                        deviceAssetId: UUID().uuidString,
                        deviceId: deviceId,
                        createdAt: now,
                        modifiedAt: now
                    )

                    try? FileManager.default.removeItem(at: tempURL)
                    successCount += 1
                } else {
                    failedUploads.append("Item \(index + 1)")
                }
            } catch {
                failedUploads.append("Item \(index + 1)")
            }
        }

        selectedPhotos = []
        phase = .loaded(())
    }

    private func updateProgress() {
        uploadProgress = totalUploads > 0 ? Float(currentUploadIndex) / Float(totalUploads) : 0
    }
}
