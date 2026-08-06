import Foundation
import Observation

@MainActor
@Observable
final class SyncViewModel {
    /// Diteruskan dari `NetworkMonitor`, tidak dipantau sendiri lagi.
    ///
    /// Dulu view model ini memegang `NWPathMonitor`-nya sendiri — dan karena ia
    /// hidup sebagai `@State` milik satu view, layar yang tidak bisa
    /// menjangkaunya (detail aset, yang dipresentasikan UIKit) tidak punya cara
    /// tahu sedang offline.
    var isOnline: Bool { NetworkMonitor.shared.isOnline }
    var isSyncing: Bool = false
    var lastSyncTime: Date?
    var syncProgress: String = ""

    private let repo: SyncRepository
    private let dataManager: SwiftDataManager

    init(repo: SyncRepository, dataManager: SwiftDataManager) {
        self.repo = repo
        self.dataManager = dataManager
    }

    func performFullSync() async {
        guard isOnline else { return }
        isSyncing = true
        syncProgress = "Syncing..."
        defer { isSyncing = false }

        do {
            try await repo.fullSync()
            lastSyncTime = Date()
            syncProgress = "Sync complete"
        } catch {
            syncProgress = "Sync failed: \(error.localizedDescription)"
        }
    }

    func performDeltaSync() async {
        guard isOnline else { return }
        isSyncing = true
        syncProgress = "Syncing changes..."
        defer { isSyncing = false }

        do {
            try await repo.deltaSync()
            lastSyncTime = Date()
            syncProgress = "Sync complete"
        } catch {
            syncProgress = "Sync failed: \(error.localizedDescription)"
        }
    }

    /// Dipakai juga oleh layar Photos, yang merender DARI hasil sync ini —
    /// karena itu statusnya harus terlihat, bukan diam-diam seperti dulu. Layar
    /// kosong yang tidak menjelaskan apa-apa selama sync pertama berjalan
    /// terlihat persis seperti aplikasi yang menggantung.
    func performBackgroundSync() async {
        guard isOnline, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let state = dataManager.getSyncState()
            if state.lastFullSyncAt == nil {
                try await repo.fullSync()
            } else {
                try await repo.deltaSync()
            }
            lastSyncTime = Date()
        } catch {
            // Silently fail for background sync
        }
    }

}
