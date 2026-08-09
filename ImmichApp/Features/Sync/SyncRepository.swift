import Foundation

class SyncRepository {
    private let api: APIClient
    private let dataManager: SwiftDataManager

    init(api: APIClient, dataManager: SwiftDataManager) {
        self.api = api
        self.dataManager = dataManager
    }

    @MainActor
    func fullSync() async throws {
        try await sync(reset: true)
    }

    @MainActor
    func deltaSync() async throws {
        try await sync(reset: false)
    }

    /// Stream diproses SAMBIL DATANG, bukan dikumpulkan dulu lalu ditulis.
    ///
    /// Versi lama menampung seluruh isi `/sync/stream` di memori — untuk
    /// perpustakaan puluhan ribu foto itu puluhan ribu DTO hidup bersamaan,
    /// lalu diubah lagi jadi puluhan ribu objek `@Model`, dan puncaknya terjadi
    /// tepat saat aplikasi baru dibuka. Sekarang tiap potongan langsung ditulis
    /// dan dilepas, jadi memorinya rata berapa pun besar perpustakaannya.
    @MainActor
    private func sync(reset: Bool, isRetryAfterReset: Bool = false) async throws {
        if reset { try dataManager.clearAllCache() }

        let outcome = try await streamAndApply(reset: reset)

        if outcome.serverRequestedReset {
            guard !isRetryAfterReset else {
                throw APIError.server(status: 409, message: "Server terus meminta sync reset")
            }
            return try await sync(reset: true, isRetryAfterReset: true)
        }

        // Konfirmasi checkpoint ke server.
        if !outcome.latestAcks.isEmpty {
            try await api.sendVoid(.json("/sync/ack", method: .post,
                                         body: SyncAckSetDTO(acks: Array(outcome.latestAcks.values))))
        }

        let state = dataManager.getSyncState()
        let now = Date()
        if reset || state.lastFullSyncAt == nil { state.lastFullSyncAt = now }
        state.lastDeltaSyncAt = now
        state.totalAssets = dataManager.cachedAssetCount()
        try dataManager.updateSyncState(state)
    }

    /// Yang tersisa setelah seluruh stream lewat — sengaja TIDAK berisi asetnya.
    private struct StreamOutcome {
        /// Ack terakhir per tipe entitas (format "type|updateId[|extraId]").
        var latestAcks: [String: String] = [:]
        var serverRequestedReset = false
    }

    /// Membaca stream dan MENULISNYA sambil jalan.
    ///
    /// Potongan sengaja tidak besar: tiap kali penuh ia langsung disimpan lalu
    /// dilepas, dan `Task.yield()` memberi main thread celah menggambar di
    /// antaranya. Itu bedanya antara "aplikasi hang saat sync pertama" dan
    /// "foto muncul sambil sync berjalan".
    private static let chunkSize = 500

    @MainActor
    private func streamAndApply(reset: Bool) async throws -> StreamOutcome {
        var request = SyncStreamRequestDTO(types: ["AssetsV1"])
        if reset { request.reset = true }

        var outcome = StreamOutcome()
        var upserts: [SyncAssetV1DTO] = []
        var deletes: [String] = []

        let lines = try await api.streamLines(.json("/sync/stream", method: .post, body: request))

        for try await line in lines {
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
            let envelope = try JSONDecoder.immich.decode(SyncLineEnvelopeDTO.self, from: data)

            switch envelope.type {
            case "AssetV1":
                let asset = try JSONDecoder.immich.decode(
                    SyncLineDataDTO<SyncAssetV1DTO>.self, from: data).data
                if asset.deletedAt != nil {
                    // Delete dari web/perangkat lain juga harus menekan fallback
                    // PhotoKit. Full sync sekaligus memperbaiki state versi app
                    // lama yang belum sempat mencatat delete secara lokal.
                    DeletedServerAssetRegistry.shared.record(
                        [asset.id], permanently: false)
                    deletes.append(asset.id)
                } else {
                    // Restore dari klien lain datang lagi sebagai AssetV1 aktif.
                    DeletedServerAssetRegistry.shared.restore([asset.id])
                    upserts.append(asset)
                }
            case "AssetDeleteV1":
                let payload = try JSONDecoder.immich.decode(
                    SyncLineDataDTO<SyncAssetDeleteV1DTO>.self, from: data).data
                DeletedServerAssetRegistry.shared.record(
                    [payload.assetId], permanently: true)
                deletes.append(payload.assetId)
            case "SyncResetV1":
                outcome.serverRequestedReset = true
                return outcome
            default:
                break // SyncAckV1/SyncCompleteV1 hanya membawa ack
            }

            if let ackType = envelope.ack.split(separator: "|").first {
                outcome.latestAcks[String(ackType)] = envelope.ack
            }

            if upserts.count >= Self.chunkSize || deletes.count >= Self.chunkSize {
                try await flush(&upserts, &deletes, isFullReset: reset)
            }
        }

        try await flush(&upserts, &deletes, isFullReset: reset)
        return outcome
    }

    @MainActor
    private func flush(
        _ upserts: inout [SyncAssetV1DTO],
        _ deletes: inout [String],
        isFullReset: Bool
    ) async throws {
        guard !upserts.isEmpty || !deletes.isEmpty else { return }

        try dataManager.applySyncBatch(
            upserts: upserts.map(makeCachedAsset),
            deletedIds: deletes,
            isFullReset: isFullReset)

        upserts.removeAll(keepingCapacity: true)
        deletes.removeAll(keepingCapacity: true)
        await Task.yield()
    }

    @MainActor
    private func makeCachedAsset(_ dto: SyncAssetV1DTO) -> CachedAsset {
        var ratio: Double?
        if let w = dto.width, let h = dto.height, w > 0, h > 0 {
            ratio = Double(w) / Double(h)
        }
        return CachedAsset(
            id: dto.id,
            assetId: dto.id,
            type: dto.type,
            isFavorite: dto.isFavorite,
            // Yang boleh tampil di linimasa HANYA `timeline`.
            //
            // Immich punya empat nilai visibility: `timeline`, `archive`,
            // `hidden`, dan `locked`. Sebelumnya cuma `archive` yang disaring,
            // jadi isi Locked Folder dan aset tersembunyi ikut masuk ke grid
            // utama. Membukanya berarti meminta `/assets/{id}` untuk sesuatu
            // yang memang tidak boleh dibaca sesi ini — dan itulah "Not found or
            // no asset.read access" yang muncul sebagai Action Failed.
            //
            // Nama fieldnya tetap `isArchived` karena artinya memang sudah itu
            // di sisi kita: "jangan tampilkan di linimasa". Layar Archived dan
            // Locked Folder tidak membacanya — keduanya bertanya langsung ke
            // endpoint pencarian dengan visibility masing-masing.
            isArchived: dto.visibility != "timeline",
            duration: ClockDuration.seconds(fromClock: dto.duration),
            livePhotoVideoId: dto.livePhotoVideoId,
            createdAt: dto.fileCreatedAt ?? dto.localDateTime ?? Date(),
            updatedAt: dto.fileModifiedAt ?? Date(),
            ratio: ratio,
            thumbhash: dto.thumbhash
        )
    }
}
