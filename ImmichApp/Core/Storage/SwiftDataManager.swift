import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class SwiftDataManager {
    static let shared = SwiftDataManager()

    let modelContainer: ModelContainer
    let modelContext: ModelContext

    private init() {
        let schema = Schema([
            CachedAsset.self, BackupRecord.self, SyncState.self,
            LocalAssetChecksum.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        self.modelContainer = try! ModelContainer(for: schema, configurations: [modelConfiguration])
        self.modelContext = ModelContext(modelContainer)
    }

    func getCachedAsset(id: String) -> CachedAsset? {
        var descriptor = FetchDescriptor<CachedAsset>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Aset linimasa sebagai nilai ringan, dibaca PER HALAMAN.
    ///
    /// Aset arsip disaring di kueri, bukan di pemanggil — menyaring setelahnya
    /// berarti sempat memuat yang tidak dipakai.
    ///
    ///
    /// Objek `@Model` bukan struct ringan: tiap satunya terikat context, punya
    /// penyimpanan balik sendiri, dan ikut dilacak perubahannya. Mengambil
    /// puluhan ribu sekaligus berarti puluhan ribu objek itu hidup BERSAMAAN —
    /// ratusan megabyte pada puncaknya, dan itu terjadi tepat saat aplikasi baru
    /// dibuka.
    ///
    /// Dengan halaman dua ribu dan context yang mati di akhir tiap halaman, yang
    /// hidup bersamaan tidak pernah lebih dari satu halaman. Yang tersisa cuma
    /// struct hasil salinannya.
    func timelineAssets() -> [TimelineRow] {
        let pageSize = 2000
        var result: [TimelineRow] = []
        var offset = 0

        while true {
            let page: [TimelineRow] = autoreleasepool {
                var descriptor = FetchDescriptor<CachedAsset>(
                    predicate: #Predicate { !$0.isArchived },
                    sortBy: [.init(\.createdAt, order: .forward)])
                descriptor.includePendingChanges = false
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = pageSize

                let context = ModelContext(modelContainer)
                let rows = (try? context.fetch(descriptor)) ?? []

                return rows.map { row in
                    TimelineRow(
                        asset: AssetLite(
                            id: row.assetId,
                            isVideo: row.type == "VIDEO",
                            ratio: row.ratio ?? 1,
                            thumbhash: row.thumbhash,
                            createdAt: row.createdAt,
                            isFavorite: row.isFavorite,
                            duration: row.duration,
                            livePhotoVideoID: row.livePhotoVideoId),
                        // Sudah dihitung saat sync; tidak ada pemformatan tanggal
                        // di jalur ini sama sekali.
                        monthKey: row.monthKey.isEmpty
                            ? MonthKey.of(row.createdAt)
                            : row.monthKey)
                }
            }

            result.append(contentsOf: page)
            offset += page.count
            if page.count < pageSize { break }
        }

        return result
    }

    func insertOrUpdateCachedAsset(_ asset: CachedAsset) throws {
        upsert(asset)
        try modelContext.save()
    }

    /// Terapkan hasil satu putaran sync dalam SATU save, bukan save per aset.
    ///
    /// - Parameter isFullReset: cache baru saja dikosongkan, jadi tidak ada yang
    ///   perlu dicari — semuanya pasti baru.
    ///
    /// Dua hal yang penting di sini:
    ///
    /// 1. Aset yang sudah ada dicari lewat SATU query untuk seluruh batch, bukan
    ///    satu query per aset. Versi lama memanggil `getCachedAsset(id:)` di
    ///    dalam loop — pada sync penuh berisi ribuan aset itu ribuan query
    ///    berurutan, semuanya di main actor, dan antarmuka membeku selama itu.
    /// 2. Ditulis lewat context SEKALI PAKAI, sama seperti jalur bacanya.
    ///    `ModelContext` menahan setiap objek yang lewat, jadi dengan context
    ///    bersama satu sync penuh meninggalkan puluhan ribu objek `@Model`
    ///    tersangkut di memori selama aplikasi hidup. Context ini mati bersama
    ///    fungsinya — datanya sudah aman di penyimpanan.
    func applySyncBatch(
        upserts: [CachedAsset],
        deletedIds: [String],
        isFullReset: Bool = false
    ) throws {
        let context = ModelContext(modelContainer)

        if isFullReset {
            for asset in upserts { context.insert(asset) }
        } else {
            let existing = fetchAssets(ids: upserts.map(\.id) + deletedIds, in: context)

            for asset in upserts {
                if let current = existing[asset.id] {
                    apply(asset, to: current)
                } else {
                    context.insert(asset)
                }
            }
            for id in deletedIds {
                if let current = existing[id] { context.delete(current) }
            }
        }

        try context.save()
    }

    /// Membuang aset dari cache lokal tanpa lewat sync.
    ///
    /// Dipakai untuk aset yang ditolak server ("Not found or no asset.read
    /// access"): entri itu tidak akan pernah datang lagi lewat delta sync —
    /// stream hanya membawa yang BERUBAH, dan dari sudut pandang server tidak ada
    /// yang berubah — jadi kalau tidak dibuang di sini ia menetap sampai ada
    /// sync penuh.
    func purgeAssets(_ ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try applySyncBatch(upserts: [], deletedIds: ids)
        // Satu titik cegat untuk SEMUA jalur yang membuang aset.
        //
        // Cache linimasa bukan satu-satunya tempat foto itu berdiri: album,
        // Favorites, dan foto per orang punya potretnya masing-masing. Mencatat
        // pembuangannya di sini berarti setiap layar bisa menyaring miliknya
        // sendiri tanpa ada yang perlu diberi tahu satu per satu.
        RemovedAssets.shared.remove(ids)
    }

    /// Dipecah per potongan: SQLite membatasi jumlah pengikat dalam satu klausa
    /// `IN`, dan daftar id sepanjang ribuan akan melewatinya.
    private func fetchAssets(
        ids: [String],
        in context: ModelContext
    ) -> [String: CachedAsset] {
        var result: [String: CachedAsset] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 400) {
            let slice = Array(ids[chunk..<min(chunk + 400, ids.count)])
            let descriptor = FetchDescriptor<CachedAsset>(
                predicate: #Predicate { slice.contains($0.id) })
            for asset in (try? context.fetch(descriptor)) ?? [] {
                result[asset.id] = asset
            }
        }
        return result
    }

    private func apply(_ asset: CachedAsset, to existing: CachedAsset) {
        existing.type = asset.type
        existing.isFavorite = asset.isFavorite
        existing.isArchived = asset.isArchived
        existing.createdAt = asset.createdAt
        existing.monthKey = asset.monthKey
        existing.updatedAt = asset.updatedAt
        existing.exifData = asset.exifData
        existing.ratio = asset.ratio
        existing.thumbhash = asset.thumbhash
        existing.duration = asset.duration
        existing.livePhotoVideoId = asset.livePhotoVideoId
    }

    private func upsert(_ asset: CachedAsset) {
        if let existing = getCachedAsset(id: asset.id) {
            apply(asset, to: existing)
        } else {
            modelContext.insert(asset)
        }
    }

    // MARK: - Tambalan dari layar lain

    /// Mengubah "ada di linimasa atau tidak" untuk aset yang SUDAH ada di cache.
    ///
    /// Dipakai layar Archived dan Locked Folder: mengembalikan foto ke linimasa
    /// harus langsung terlihat di tab Photos, bukan menunggu sync berikutnya.
    /// Linimasa dirender dari cache ini, jadi menambalnya di sini sama dengan
    /// menambal layarnya.
    func setTimelineVisibility(_ ids: [String], inTimeline: Bool) throws {
        guard !ids.isEmpty else { return }
        for asset in fetchAssets(ids: ids, in: modelContext).values {
            asset.isArchived = !inTimeline
        }
        try modelContext.save()
    }

    /// Mengembalikan aset ke cache linimasa dari data seadanya.
    ///
    /// Untuk restore dari tong sampah: aset yang dibuang sudah TIDAK ADA di
    /// cache, jadi tidak ada yang bisa ditambal — ia harus ditulis ulang. Yang
    /// tersedia cuma yang dibawa layar sampah (`AssetLite`), dan itu cukup:
    /// petak grid hanya butuh rasio, thumbhash, tanggal, dan durasi. Sisanya
    /// menyusul saat sync berikutnya menimpanya.
    func restoreToTimeline(_ assets: [AssetLite]) throws {
        guard !assets.isEmpty else { return }
        for asset in assets {
            let cached = CachedAsset(
                id: asset.id,
                assetId: asset.id,
                type: asset.isVideo ? "VIDEO" : "IMAGE",
                isFavorite: asset.isFavorite,
                isArchived: false,
                duration: asset.duration,
                livePhotoVideoId: asset.livePhotoVideoID,
                createdAt: asset.createdAt,
                updatedAt: Date(),
                ratio: asset.ratio,
                thumbhash: asset.thumbhash)
            upsert(cached)
        }
        try modelContext.save()
    }

    func cachedAssetCount() -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<CachedAsset>())) ?? 0
    }

    /// Jumlah aset yang benar-benar MASUK LINIMASA.
    ///
    /// Berbeda dari `cachedAssetCount`, yang menghitung semuanya termasuk arsip
    /// — angka itu benar untuk pembukuan sync, tapi salah untuk menjawab "apakah
    /// ada yang bisa digambar sekarang". Cache yang isinya arsip semua akan
    /// menjawab "ada", lalu linimasanya ternyata kosong.
    func timelineAssetCount() -> Int {
        (try? modelContext.fetchCount(
            FetchDescriptor<CachedAsset>(predicate: #Predicate { !$0.isArchived }))) ?? 0
    }

    func deleteCachedAsset(id: String) throws {
        if let asset = getCachedAsset(id: id) {
            modelContext.delete(asset)
            try modelContext.save()
        }
    }

    func clearAllCache() throws {
        try modelContext.delete(model: CachedAsset.self)
        try modelContext.save()
    }

    /// Menghapus seluruh data yang terikat akun dari penyimpanan lokal.
    ///
    /// Berbeda dari `clearAllCache()`, yang sengaja hanya membuang linimasa saat
    /// full sync. Logout juga harus menghapus checkpoint sync, pasangan backup,
    /// dan checksum lokal agar akun berikutnya tidak mewarisi keadaan akun lama.
    func clearAllAccountData() throws {
        try modelContext.delete(model: CachedAsset.self)
        try modelContext.delete(model: BackupRecord.self)
        try modelContext.delete(model: SyncState.self)
        try modelContext.delete(model: LocalAssetChecksum.self)
        try modelContext.save()
    }

    func getBackupRecord(deviceAssetId: String) -> BackupRecord? {
        var descriptor = FetchDescriptor<BackupRecord>(predicate: #Predicate { $0.deviceAssetId == deviceAssetId })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Semua `localIdentifier` yang pernah diunggah lewat aplikasi ini.
    ///
    /// Inilah satu-satunya cara murah menjawab "foto di perangkat ini sudah ada
    /// di server atau belum". Yang TIDAK terjawab olehnya: foto yang diunggah
    /// dari web atau perangkat lain — ia akan terbaca "hanya di perangkat"
    /// sampai diunggah dari sini. Alternatifnya mencocokkan checksum, dan itu
    /// berarti membaca byte penuh setiap foto di pustaka.
    func uploadedLocalIdentifiers() -> Set<String> {
        let descriptor = FetchDescriptor<BackupRecord>(
            predicate: #Predicate { $0.localIdentifier != "" })
        let records = (try? modelContext.fetch(descriptor)) ?? []
        return Set(records.map(\.localIdentifier))
    }

    /// Id ASET SERVER yang salinan perangkatnya diketahui.
    ///
    /// Pasangan dari `uploadedLocalIdentifiers`, dibaca dari arah sebaliknya:
    /// yang satu menjawab "petak lokal ini perlu ditampilkan?", yang ini
    /// menjawab "petak server ini juga ada di perangkat?".
    func uploadedServerAssetIDs() -> Set<String> {
        let descriptor = FetchDescriptor<BackupRecord>(
            predicate: #Predicate { $0.localIdentifier != "" })
        let records = (try? modelContext.fetch(descriptor)) ?? []
        return Set(records.map(\.assetId))
    }

    /// Pasangan lengkapnya: `localIdentifier` → id aset server.
    ///
    /// Dua kerabatnya di atas masing-masing hanya mengembalikan satu sisi, dan
    /// itu cukup untuk menjawab "sudah ada?". Yang ini diperlukan saat sisi
    /// SEBERANGNYA yang dibutuhkan — menyusun aset server ke dalam album
    /// berdasarkan album perangkat asalnya.
    func serverAssetIDsByLocalIdentifier() -> [String: String] {
        let descriptor = FetchDescriptor<BackupRecord>(
            predicate: #Predicate { $0.localIdentifier != "" })
        let records = (try? modelContext.fetch(descriptor)) ?? []
        return Dictionary(records.map { ($0.localIdentifier, $0.assetId) },
                          uniquingKeysWith: { first, _ in first })
    }

    /// `PHAsset.localIdentifier` milik sebuah aset server, kalau salinan
    /// perangkatnya diketahui.
    func localIdentifier(forServerAsset id: String) -> String? {
        var descriptor = FetchDescriptor<BackupRecord>(
            predicate: #Predicate { $0.assetId == id && $0.localIdentifier != "" })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first?.localIdentifier
    }

    /// Melupakan salinan perangkat, TANPA melupakan unggahannya.
    ///
    /// Dipakai setelah foto dihapus dari pustaka perangkat: asetnya tetap ada di
    /// server, jadi catatannya harus bertahan supaya tidak terunggah dua kali.
    /// Yang tidak berlaku lagi hanya kaitannya ke berkas yang sudah tidak ada.
    func unlinkDeviceAsset(localIdentifier: String) throws {
        let descriptor = FetchDescriptor<BackupRecord>(
            predicate: #Predicate { $0.localIdentifier == localIdentifier })
        for record in (try? modelContext.fetch(descriptor)) ?? [] {
            record.localIdentifier = ""
        }
        try modelContext.save()
    }

    // MARK: - Checksum foto perangkat

    /// Checksum yang sudah pernah dihitung, dipetakan dari `localIdentifier`.
    func storedChecksums() -> [String: String] {
        let records = (try? modelContext.fetch(FetchDescriptor<LocalAssetChecksum>())) ?? []
        return Dictionary(records.map { ($0.localIdentifier, $0.checksum) },
                          uniquingKeysWith: { first, _ in first })
    }

    func storeChecksums(_ entries: [(localIdentifier: String, checksum: String)]) throws {
        guard !entries.isEmpty else { return }
        for entry in entries {
            modelContext.insert(LocalAssetChecksum(
                localIdentifier: entry.localIdentifier, checksum: entry.checksum))
        }
        try modelContext.save()
    }

    /// Menandai satu foto perangkat sebagai "sudah ada di server".
    ///
    /// Memakai `BackupRecord` yang sama dengan jalur unggah, bukan tabel baru:
    /// yang dicatat memang hal yang sama — foto perangkat ini berpasangan dengan
    /// aset server itu — dan yang membedakan cuma siapa yang mengunggahnya.
    func linkDeviceAsset(localIdentifier: String, to serverAssetID: String) throws {
        let descriptor = FetchDescriptor<BackupRecord>(
            predicate: #Predicate { $0.localIdentifier == localIdentifier })
        // Fetch yang GAGAL menghasilkan nil, dan nil tidak boleh dibaca sebagai
        // "belum ada" — itu menyisipkan catatan kembar setiap kali.
        guard let existing = try? modelContext.fetch(descriptor), existing.isEmpty
        else { return }

        modelContext.insert(BackupRecord(
            id: UUID().uuidString,
            assetId: serverAssetID,
            deviceAssetId: "",
            localIdentifier: localIdentifier))
        try modelContext.save()
    }

    func insertBackupRecord(_ record: BackupRecord) throws {
        modelContext.insert(record)
        try modelContext.save()
    }

    func getSyncState() -> SyncState {
        if let state = try? modelContext.fetch(FetchDescriptor<SyncState>()).first {
            return state
        }
        let state = SyncState()
        modelContext.insert(state)
        try? modelContext.save()
        return state
    }

    func updateSyncState(_ state: SyncState) throws {
        try modelContext.save()
    }
}
