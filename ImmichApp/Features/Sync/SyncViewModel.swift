import Foundation
import Observation
import Network

@MainActor
@Observable
final class SyncViewModel {
    var isOnline: Bool = true
    var isSyncing: Bool = false
    var lastSyncTime: Date?
    var syncProgress: String = ""

    private let repo: SyncRepository
    private let dataManager: SwiftDataManager
    private let monitor = NWPathMonitor()

    init(repo: SyncRepository, dataManager: SwiftDataManager) {
        self.repo = repo
        self.dataManager = dataManager
        setupNetworkMonitoring()
    }

    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
            }
        }
        let queue = DispatchQueue(label: "network-monitor")
        monitor.start(queue: queue)
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

    func performBackgroundSync() async {
        guard isOnline else { return }

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

    deinit {
        monitor.cancel()
    }
}
