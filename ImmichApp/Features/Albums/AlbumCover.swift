import Observation
import SwiftUI

/// Penyelesai sampul album.
///
/// `albumThumbnailAssetId` di Immich BOLEH kosong. Kolomnya nullable, dan server
/// hanya mengisinya di jalur-jalur tertentu — saat album dibuat lewat API dengan
/// aset, saat aset pertama ditambahkan lewat API, atau saat pengguna memilih
/// sampul sendiri. Album yang isinya masuk lewat jalur lain (impor CLI, external
/// library, job latar) sah-sah saja punya sampul null selamanya.
///
/// Selama ini setiap tempat yang menggambar sampul menulis
/// `if let album.albumThumbnailAssetId { … } else { kotak abu-abu }` sendiri —
/// lima salinan, semuanya menganggap field itu pasti terisi. Ketika server
/// mengirim null, yang muncul kotak abu-abu, dan tidak ada satu pun yang mencoba
/// mencari gantinya.
///
/// Jadi sampul TIDAK lagi diperlakukan sebagai field, melainkan sesuatu yang
/// DISELESAIKAN: pakai yang dari server kalau ada, kalau tidak ambil aset
/// terbaru album itu.
@MainActor
@Observable
final class AlbumCoverStore {
    static let shared = AlbumCoverStore()

    /// Hasil yang sudah pernah diselesaikan.
    ///
    /// Nilainya sengaja `String?` DI DALAM kamus: nil berarti "sudah dicoba dan
    /// albumnya memang tidak punya apa-apa", yang berbeda dari "belum pernah
    /// dicoba" (kuncinya tidak ada). Tanpa pembedaan itu album kosong akan
    /// diminta ulang setiap kali kartunya lewat di layar.
    ///
    /// Ini SATU-SATUNYA properti yang diamati: begitu satu kartu berhasil
    /// menyelesaikan sampulnya, semua kartu album yang sama di layar lain —
    /// baris Library, grid Albums, sheet pemilih — ikut tergambar ulang.
    private var resolved: [String: String?] = [:]

    /// Permintaan yang sedang berjalan, supaya beberapa kartu album yang sama
    /// tidak menembak endpoint yang sama berbarengan.
    ///
    /// Diabaikan observasi: ini pembukuan internal, dan mengamatinya berarti
    /// setiap kartu tergambar ulang dua kali percuma (saat permintaan dicatat
    /// dan saat dihapus).
    @ObservationIgnored
    private var inFlight: [String: Task<Result<String?, Error>, Never>] = [:]

    /// Penanda "angkatan" data.
    ///
    /// Dinaikkan tiap `clear()`. Permintaan yang sedang menggantung saat logout
    /// tetap akan selesai dan kembali ke sini — tanpa penanda ini, id aset milik
    /// akun LAMA akan ditulis balik ke `resolved` setelah dibersihkan, dan
    /// pembersihannya jadi percuma.
    @ObservationIgnored
    private var generation = 0

    private init() {}

    /// Sampul yang berlaku sekarang — dari server kalau ada, kalau tidak hasil
    /// yang sudah diselesaikan. Sinkron, karena inilah yang dibaca `body`.
    func coverID(for album: AlbumResponseDTO) -> String? {
        if let id = album.albumThumbnailAssetId { return id }
        // Subscript kamus bernilai opsional mengembalikan `String??`; `?? nil`
        // meratakannya jadi satu lapis.
        return resolved[album.id] ?? nil
    }

    func resolveCover(for album: AlbumResponseDTO, session: SessionManager) async {
        // Server sudah menyebutkan sampulnya; tidak ada yang perlu dicari.
        guard album.albumThumbnailAssetId == nil else { return }
        // `keys.contains`, bukan `resolved[id] == nil`: nilai kamusnya sendiri
        // opsional, jadi perbandingan dengan nil tidak bisa membedakan "sudah
        // dicoba, hasilnya kosong" dari "belum pernah dicoba".
        guard !resolved.keys.contains(album.id) else { return }

        // Kartu lain sudah menanyakannya. Cukup tunggu; hasilnya ditulis oleh
        // pemanggil pertama dan view ini tergambar ulang karena `resolved`
        // diamati.
        if let running = inFlight[album.id] {
            _ = await running.value
            return
        }

        // Album kosong tidak punya apa pun untuk dijadikan sampul; tidak ada
        // gunanya menanyakannya ke server.
        guard album.assetCount > 0 else {
            remember(nil, for: album.id)
            return
        }

        let albumID = album.id
        let expectedGeneration = generation
        let task = Task<Result<String?, Error>, Never> {
            let repo = AlbumRepository(api: APIClient(session: session))
            do {
                let detail = try await repo.detail(albumID)
                // Yang TERBARU, bukan `assets.first`: urutan yang dikirim server
                // mengikuti setelan `order` milik album, jadi elemen pertama bisa
                // yang tertua atau yang termuda tergantung albumnya. Memilih
                // lewat tanggal membuat sampulnya sama di mana pun.
                return .success(
                    detail.assets?.max(by: { $0.fileCreatedAt < $1.fileCreatedAt })?.id)
            } catch {
                return .failure(error)
            }
        }
        inFlight[albumID] = task
        let outcome = await task.value

        // Sudah ganti akun selagi permintaan ini berjalan — hasilnya milik data
        // yang sudah dibuang, termasuk `inFlight` yang mungkin sudah diisi
        // permintaan baru untuk album lain.
        guard expectedGeneration == generation else { return }
        if inFlight[albumID] == task { inFlight[albumID] = nil }

        // Kegagalan jaringan TIDAK dicatat. Kalau dicatat, satu permintaan yang
        // meleset membuat album itu memakai kotak abu-abu sampai aplikasi
        // ditutup — padahal sampulnya ada, cuma gagal diambil sekali.
        guard case .success(let id) = outcome else { return }
        remember(id, for: albumID)
    }

    /// Dipanggil saat logout: id album milik akun lama tidak boleh menempel di
    /// akun berikutnya.
    func clear() {
        generation &+= 1
        resolved.removeAll()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }

    /// `resolved[id] = nil` akan MENGHAPUS kuncinya, bukan menyimpan nil —
    /// jebakan lama Swift untuk kamus bernilai opsional. `updateValue` menyimpan
    /// nilainya apa adanya.
    private func remember(_ assetID: String?, for albumID: String) {
        resolved.updateValue(assetID, forKey: albumID)
    }
}

/// Sampul album — satu-satunya tempat sampul digambar.
///
/// Mengisi frame yang diberikan pemanggil; ukuran dan pemotongan sudutnya
/// ditentukan di tempat pemakaian.
struct AlbumCoverImage: View {
    let album: AlbumResponseDTO
    /// Ukuran yang diminta ke server. "thumbnail" untuk kartu, "preview" untuk
    /// pratinjau besar.
    var size: String = "thumbnail"
    var pixelSize: Int? = nil
    /// Besar ikon pengganti saat albumnya benar-benar tidak punya sampul.
    var placeholderFont: Font = .body

    @Environment(SessionManager.self) private var session

    var body: some View {
        ZStack {
            if let coverID = AlbumCoverStore.shared.coverID(for: album) {
                AuthImage(assetId: coverID, size: size, pixelSize: pixelSize)
            } else {
                Rectangle()
                    .fill(.fill.tertiary)
                    .overlay {
                        Image(systemName: "photo.on.rectangle")
                            .font(placeholderFont)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .task(id: album.id) {
            await AlbumCoverStore.shared.resolveCover(for: album, session: session)
        }
    }
}
