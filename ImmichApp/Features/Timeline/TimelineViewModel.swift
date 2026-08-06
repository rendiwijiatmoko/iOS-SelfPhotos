import Foundation
import Observation
// Untuk withAnimation saat membuang aset dari grid.
import SwiftUI

@MainActor
@Observable
final class TimelineViewModel {
    var sections: [TimelineSection] = []
    /// Daftar datar seluruh foto, disimpan bukan dihitung.
    ///
    /// Layar detail memerlukannya sebagai isi pager. Sebagai properti terhitung,
    /// ia diratakan ulang setiap kali penutup fullScreenCover dievaluasi —
    /// termasuk pada SETIAP usapan halaman, karena foto yang tampil ikut berubah.
    /// Pada puluhan ribu foto itu penyalinan array penuh per usapan.
    private(set) var allAssets: [AssetLite] = []
    var phase: LoadingPhase<Void> = .idle
    var albums: [AlbumResponseDTO] = []
    var actionError: String?

    /// Ada foto di cache lokal, diketahui SEBELUM apa pun dibaca.
    ///
    /// Ini yang membedakan "belum ada apa-apa, tunggu sync" dari "sudah ada,
    /// sebentar lagi tergambar". Yang pertama pantas diberi spinner; yang kedua
    /// tidak — foto yang sudah ada di perangkat tidak sedang diunduh dari mana
    /// pun, dan memberinya spinner membuat aplikasi terasa selalu memuat ulang
    /// tiap kali dibuka.
    ///
    /// `fetchCount` saja, bukan membaca isinya: satu hitungan di SQLite, bukan
    /// puluhan ribu objek.
    private(set) var hasLocalData = false

    /// Sidik jari isi linimasa terakhir yang berhasil disusun.
    private var signature: Signature?
    private var hasLoaded = false

    private let dataManager: SwiftDataManager?
    private let assetRepo: AssetDetailRepository?
    private let albumRepo: AlbumRepository?

    init(
        dataManager: SwiftDataManager? = nil,
        assetRepo: AssetDetailRepository? = nil,
        albumRepo: AlbumRepository? = nil
    ) {
        self.dataManager = dataManager
        self.assetRepo = assetRepo
        self.albumRepo = albumRepo
        self.hasLocalData = (dataManager?.timelineAssetCount() ?? 0) > 0

        // Linimasa yang memasang telinganya, bukan pemuat gambar yang memanggil
        // linimasa: pemuat tidak boleh tahu apa pun soal penyimpanan maupun
        // grid. `weak self` karena kotak suratnya hidup selama aplikasi hidup.
        UnreadableAssets.shared.onPurge = { [weak self] ids in
            self?.purgeUnreadable(ids)
        }
    }

    /// Aset yang ditolak server dibuang dari cache DAN dari grid.
    ///
    /// Dua-duanya perlu: membuang dari grid saja membuatnya muncul lagi pada
    /// muat ulang berikutnya, sedangkan membuang dari cache saja membiarkan
    /// petak matinya tetap terlihat sampai layar disusun ulang.
    func purgeUnreadable(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        try? dataManager?.purgeAssets(Array(ids))

        // Pemuat thumbnail yang sama dipakai grid album, favorit, orang, arsip,
        // dan trash — laporannya belum tentu tentang foto yang ada di linimasa.
        // Tanpa penjaga ini, satu gelombang kegagalan di layar lain menjalankan
        // animasi pembuangan yang tidak membuang apa pun DAN membatalkan sidik
        // jari linimasa, yang berarti seluruh cache dibaca ulang percuma.
        guard allAssets.contains(where: { ids.contains($0.id) }) else { return }
        removeAssets(ids)
    }

    // MARK: - Pemuatan

    /// Linimasa dibangun dari CACHE LOKAL, bukan dari `/timeline/buckets`.
    ///
    /// Jalur lama menarik daftar bucket, lalu satu permintaan lagi per bulan yang
    /// masing-masing berisi seluruh aset bulan itu. Pada perpustakaan puluhan ribu
    /// foto itu berarti puluhan respons besar yang harus di-decode justru sambil
    /// pengguna menggulir.
    ///
    /// Aplikasi resmi tidak menyentuh endpoint itu sama sekali: ia menstream
    /// `/sync/stream` satu kali, menyimpan hasilnya secara lokal, lalu merender
    /// dari sana. Itulah yang membuatnya terasa seketika — dan stream yang sama
    /// sudah kita jalankan, hanya belum dipakai sebagai sumber utama.
    func loadTimeline() async {
        // Spinner HANYA kalau memang tidak ada apa-apa di perangkat.
        //
        // Membaca cache dan mengelompokkannya butuh sepersekian detik pada
        // perpustakaan besar. Menandainya sebagai "memuat" membuat aplikasi
        // membuka dengan spinner setiap kali, padahal fotonya sudah ada di
        // perangkat dan tidak ada yang sedang diunduh.
        if sections.isEmpty, !hasLocalData { phase = .loading }
        await rebuild()
    }

    /// Dipakai `task` layar, yang berjalan ulang SETIAP KALI tab dibuka lagi.
    ///
    /// Membaca ulang seluruh cache tiap perpindahan tab itu mahal — pada
    /// perpustakaan puluhan ribu foto, itulah jeda berdetik-detik saat berpindah.
    /// Linimasa hanya berubah lewat sync atau aksi lokal, dan keduanya sudah
    /// memuat ulang sendiri, jadi pembukaan tab tidak perlu melakukan apa pun.
    func loadTimelineIfNeeded() async {
        guard !hasLoaded else { return }
        await loadTimeline()
    }

    private func rebuild() async {
        let rows = dataManager?.timelineAssets() ?? []
        hasLocalData = !rows.isEmpty

        guard !rows.isEmpty else {
            // Belum ada apa pun secara lokal. Bukan kegagalan — sync mungkin
            // masih berjalan; layar kosongnya yang menjelaskan.
            //
            // `hasLoaded` sengaja TIDAK disetel: tidak ada yang berhasil disusun,
            // jadi pembukaan tab berikutnya masih boleh mencoba lagi.
            sections = []
            allAssets = []
            signature = nil
            phase = .loaded(())
            // Kosong pun tetap "siap": splash-nya menutupi pembacaan cache, dan
            // cache yang memang kosong sudah selesai dibaca.
            AppLaunchState.shared.markReady()
            return
        }

        // Tidak menyusun ulang kalau isinya sama.
        //
        // Sebagian besar delta sync tidak mengubah apa pun. Tanpa penjaga ini,
        // setiap sync tetap mengganti seluruh array `sections` — SwiftUI lalu
        // membanding-bandingkan ulang seluruh grid, dan posisi gulir pengguna
        // ikut terguncang tanpa ada satu foto pun yang berubah.
        let newSignature = Signature(rows)
        guard newSignature != signature else {
            hasLoaded = true
            phase = .loaded(())
            AppLaunchState.shared.markReady()
            return
        }

        // Pengelompokan dilakukan DI LUAR main actor.
        //
        // Puluhan ribu iterasi plus pembangunan array section bukan pekerjaan
        // yang boleh menahan antarmuka — dan tidak ada satu pun bagiannya yang
        // butuh main thread.
        let built = await Self.build(rows)

        signature = newSignature
        sections = built.sections
        allAssets = built.assets
        hasLoaded = true
        phase = .loaded(())
        AppLaunchState.shared.markReady()
    }

    /// Sidik jari murah untuk isi linimasa.
    ///
    /// Cukup jumlah plus aset di kedua ujungnya: penambahan, penghapusan, dan
    /// perubahan tanggal semuanya menggeser salah satu dari ketiganya. Menyusuri
    /// seluruh id hanya akan mengulang pekerjaan yang justru ingin dihindari.
    private struct Signature: Equatable {
        let count: Int
        let firstID: String?
        let lastID: String?

        init(_ rows: [TimelineRow]) {
            count = rows.count
            firstID = rows.first?.asset.id
            lastID = rows.last?.asset.id
        }
    }

    func retry() async {
        await loadTimeline()
    }

    /// Aset TERBARU untuk sebuah id.
    ///
    /// Grid UIKit memegang salinan yang dibekukan saat snapshot terakhir
    /// disusun, dan snapshot itu sengaja tidak disusun ulang kalau daftarnya
    /// tidak berubah. Pencarian linier di sini tidak masalah: yang memanggilnya
    /// cuma ketukan dan tekan-lama, bukan penggambaran sel.
    func asset(for id: String) -> AssetLite? {
        allAssets.first { $0.id == id }
    }

    /// Mengelompokkan per bulan dalam SATU lintasan, di luar main actor.
    ///
    /// Barisnya sudah terurut menaik dari kueri dan kunci bulannya sudah dihitung
    /// saat sync, jadi cukup memutus setiap kali kuncinya berganti — tanpa kamus
    /// perantara, pengurutan ulang, maupun pemformatan tanggal.
    nonisolated private static func build(
        _ rows: [TimelineRow]
    ) async -> (sections: [TimelineSection], assets: [AssetLite]) {
        await Task.detached(priority: .userInitiated) {
            var sections: [TimelineSection] = []
            sections.reserveCapacity(64)
            var assets: [AssetLite] = []
            assets.reserveCapacity(rows.count)
            for (offset, row) in rows.enumerated() {
                assets.append(row.asset)

                if sections.isEmpty || sections[sections.count - 1].id != row.monthKey {
                    sections.append(TimelineSection(
                        id: row.monthKey,
                        title: formatBucketTitle(row.monthKey),
                        assets: [row.asset],
                        count: 1,
                        startIndex: offset))
                } else {
                    sections[sections.count - 1].assets.append(row.asset)
                    sections[sections.count - 1].count += 1
                }
            }
            return (sections, assets)
        }.value
    }

    // MARK: - Aksi context menu

    /// Daftar album untuk "Add to Album"; cukup dimuat sekali.
    func loadAlbumsIfNeeded() async {
        guard albums.isEmpty, let albumRepo else { return }
        albums = (try? await albumRepo.all()) ?? []
    }

    /// Toggle, bukan selalu menyalakan — context menu memakai teks
    /// "Favorite"/"Unfavorite" sesuai status sekarang.
    ///
    /// - Returns: true kalau server menerimanya, supaya pemanggil bisa memberi
    ///   umpan balik getar hanya saat perubahannya benar-benar terjadi.
    @discardableResult
    func toggleFavorite(_ asset: AssetLite) async -> Bool {
        guard let assetRepo else { return false }
        let newValue = !asset.isFavorite
        do {
            try await assetRepo.toggleFavorite(asset.id, to: newValue)
            setFavorite(asset.id, to: newValue)
            return true
        } catch {
            actionError = Self.describe(error)
            return false
        }
    }

    /// Menambal status favorit di grid tanpa refetch — dipakai juga oleh layar
    /// detail lewat callback.
    ///
    /// DUA-DUANYA ditambal, `sections` dan `allAssets`.
    ///
    /// Dulu hanya `sections`, dan `allAssets` dibiarkan basi. Itu tidak terlihat
    /// di grid — sel menggambar dari `sections` — tapi `asset(for:)` membaca
    /// `allAssets`, dan itulah yang dipakai context menu untuk memutuskan
    /// tulisannya. Hasilnya: foto yang baru saja difavoritkan tetap menawarkan
    /// "Favorite", tidak pernah "Unfavorite".
    func setFavorite(_ id: String, to value: Bool) {
        for sectionIndex in sections.indices {
            guard let assetIndex = sections[sectionIndex].assets
                .firstIndex(where: { $0.id == id }) else { continue }
            sections[sectionIndex].assets[assetIndex].isFavorite = value
            break
        }
        if let index = allAssets.firstIndex(where: { $0.id == id }) {
            allAssets[index].isFavorite = value
        }
    }

    func archive(_ asset: AssetLite) async {
        guard let assetRepo else { return }
        do {
            try await assetRepo.toggleArchive(asset.id, to: true)
            removeAsset(asset.id)
            // Cache lokal ikut ditambal, bukan cuma gridnya.
            //
            // Linimasa dirender DARI cache itu; membuang selnya saja berarti
            // fotonya muncul lagi pada rebuild berikutnya — dan rebuild terjadi
            // pada ketukan kedua tab Photos maupun setiap sync selesai.
            try? dataManager?.setTimelineVisibility([asset.id], inTimeline: false)
        } catch {
            actionError = Self.describe(error)
        }
    }

    @discardableResult
    func delete(_ asset: AssetLite) async -> Bool {
        guard let assetRepo else { return false }
        do {
            try await assetRepo.delete(asset.id)
            removeAsset(asset.id)
            // Dihapus berarti BUANG dari cache, bukan disembunyikan.
            try? dataManager?.purgeAssets([asset.id])
            return true
        } catch {
            actionError = Self.describe(error)
            return false
        }
    }

    /// Favorit MASSAL selalu menyalakan, bukan membalik satu per satu.
    ///
    /// Seleksi bisa berisi campuran; membalik masing-masing akan menghasilkan
    /// separuh menyala separuh padam — hasil yang tidak diminta siapa pun.
    @discardableResult
    func favoriteSelected(_ ids: [String]) async -> Bool {
        guard let assetRepo, !ids.isEmpty else { return false }
        do {
            for id in ids {
                try await assetRepo.toggleFavorite(id, to: true)
                setFavorite(id, to: true)
            }
            return true
        } catch {
            actionError = Self.describe(error)
            return false
        }
    }

    /// Memindahkan seleksi ke arsip; fotonya keluar dari linimasa.
    @discardableResult
    func archiveSelected(_ ids: [String]) async -> Bool {
        guard let assetRepo, !ids.isEmpty else { return false }
        do {
            for id in ids {
                try await assetRepo.toggleArchive(id, to: true)
            }
            removeAssets(Set(ids))
            try? dataManager?.setTimelineVisibility(ids, inTimeline: false)
            return true
        } catch {
            actionError = Self.describe(error)
            return false
        }
    }

    /// Memindahkan ke folder terkunci; fotonya keluar dari linimasa.
    @discardableResult
    func lockSelected(_ ids: [String]) async -> Bool {
        guard let assetRepo, !ids.isEmpty else { return false }
        do {
            for id in ids {
                try await assetRepo.setVisibility(id, to: .locked)
            }
            removeAssets(Set(ids))
            try? dataManager?.setTimelineVisibility(ids, inTimeline: false)
            return true
        } catch {
            actionError = Self.describe(error)
            return false
        }
    }

    @discardableResult
    func deleteSelected(_ ids: [String]) async -> Bool {
        guard let assetRepo, !ids.isEmpty else { return false }
        do {
            try await assetRepo.delete(ids)
            removeAssets(Set(ids))
            try? dataManager?.purgeAssets(ids)
            return true
        } catch {
            actionError = Self.describe(error)
            return false
        }
    }

    /// Unduh beberapa file asli sekaligus untuk share sheet. Yang gagal dilewati,
    /// bukan membatalkan seluruh operasi.
    func shareURLs(for ids: [String]) async -> [URL] {
        guard let assetRepo else { return [] }
        var urls: [URL] = []
        for id in ids {
            guard let data = try? await assetRepo.downloadOriginal(id) else { continue }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(id).jpg")
            if (try? data.write(to: url)) != nil {
                urls.append(url)
            }
        }
        return urls
    }

    func addToAlbum(_ asset: AssetLite, album: AlbumResponseDTO) async {
        await addToAlbum([asset.id], album: album)
    }

    func addToAlbum(_ ids: [String], album: AlbumResponseDTO) async {
        guard let albumRepo, !ids.isEmpty else { return }
        do {
            let duplicates = try await albumRepo.addAssets(ids, to: album.id)
            if !duplicates.isEmpty {
                // "Sudah ada di album" bukan kegagalan, tapi tetap harus
                // terdengar — tanpa itu aksinya tidak menghasilkan apa pun
                // yang terlihat.
                actionError = String(localized: "Already in this album")
            }
        } catch {
            actionError = Self.describe(error)
        }
    }

    /// Unduh file asli ke lokasi sementara untuk dibagikan lewat share sheet
    /// (URL server polos akan kena 401).
    func shareURL(for asset: AssetLite) async -> URL? {
        guard let assetRepo else { return nil }
        do {
            let data = try await assetRepo.downloadOriginal(asset.id)
            let filename = "\(asset.id).\(asset.isVideo ? "mov" : "jpg")"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url)
            return url
        } catch {
            actionError = Self.describe(error)
            return nil
        }
    }

    /// Buang aset dari grid setelah dipindah/dihapus di layar detail.
    func assetWasRemoved(_ id: String) {
        removeAsset(id)
    }

    /// Metadata aset berubah di layar detail (tanggal, lokasi, deskripsi).
    ///
    /// Tanggal ikut menentukan bulan tempat foto itu berada, jadi perubahannya
    /// tidak cukup ditambal per sel — linimasanya disusun ulang. Sumbernya cache
    /// lokal, jadi ini murni pekerjaan di perangkat, bukan permintaan baru.
    func assetWasUpdated(_ id: String) async {
        await loadTimeline()
    }

    /// Menghapus banyak aset dalam SATU transaksi animasi.
    ///
    /// Memanggil `removeAsset` per id akan memicu animasi terpisah untuk tiap
    /// foto, sehingga grid terlihat berkedut menyusun ulang berkali-kali.
    private func removeAssets(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            for idx in sections.indices {
                sections[idx].assets.removeAll { ids.contains($0.id) }
                sections[idx].count = sections[idx].assets.count
            }
            sections.removeAll { $0.assets.isEmpty }
            allAssets.removeAll { ids.contains($0.id) }
            // Kalau yang terakhir ikut terbuang, tidak ada lagi yang "sudah ada
            // di perangkat" — dan pemuatan berikutnya memang pantas diberi
            // spinner.
            hasLocalData = !allAssets.isEmpty
            reindex()
            // Isinya baru saja berubah di klien; sidik jari lama tidak lagi
            // mewakili apa pun, dan menahannya akan membuat muat ulang
            // berikutnya dilewati.
            signature = nil
        }
    }

    private func removeAsset(_ id: String) {
        removeAssets([id])
    }

    /// `startIndex` adalah posisi foto pertama sebuah bulan dalam urutan datar.
    ///
    /// Grid memakainya untuk tahu bulan apa yang sedang tampil tanpa memecah
    /// dirinya per bulan, jadi setelah ada foto yang dibuang offsetnya harus
    /// dirapatkan lagi — kalau tidak, judul bulan di toolbar meleset.
    private func reindex() {
        var offset = 0
        for index in sections.indices {
            sections[index].startIndex = offset
            offset += sections[index].assets.count
        }
    }

    private static func describe(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }

    /// Dipanggil sekali per SECTION, bukan per aset — jumlahnya belasan sampai
    /// ratusan, jadi `DateFormatter` di sini tidak masalah.
    nonisolated static func formatBucketTitle(_ bucket: String) -> String {
        guard let date = MonthKey.date(from: bucket) else { return bucket }
        return monthTitleFormatter.string(from: date)
    }
}

private let monthTitleFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = .current
    f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
    return f
}()
