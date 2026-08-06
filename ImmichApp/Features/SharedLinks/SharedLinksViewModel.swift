import Foundation
import Observation

@MainActor
@Observable
final class SharedLinksViewModel {
    var links: [SharedLinkDTO] = []
    var phase: LoadingPhase<Void> = .idle

    private let repo: SharedLinkRepository

    init(repo: SharedLinkRepository) {
        self.repo = repo
    }

    func load() async {
        phase = .loading
        do {
            links = try await fetch()
            phase = .loaded(())
        } catch {
            phase = .failed(message(for: error, fallback: "Failed to load shared links"))
        }
    }

    /// Muat ulang TANPA mengosongkan layar.
    ///
    /// `load()` memasang `.loading`, dan itu menukar daftarnya dengan spinner
    /// selayar penuh — termasuk melenyapkan kontrol tarik-untuk-menyegarkan yang
    /// sedang dipegang jari, di tengah gerakannya. Kegagalannya pun tidak boleh
    /// menghapus daftar yang sudah terlihat.
    ///
    /// - Returns: pesan kesalahan, atau nil kalau berhasil.
    func refresh() async -> String? {
        do {
            links = try await fetch()
            phase = .loaded(())
            return nil
        } catch {
            return message(for: error, fallback: "Failed to load shared links")
        }
    }

    func retry() async {
        await load()
    }

    /// - Returns: pesan kesalahan, atau nil kalau berhasil.
    func update(_ id: String, edit: SharedLinkEditDTO) async -> String? {
        do {
            let updated = try await repo.update(id, edit: edit)
            guard let index = links.firstIndex(where: { $0.id == id }) else { return nil }

            // Ditambal DI TEMPAT, bukan memuat ulang seluruh daftar: hasil PATCH
            // sudah berisi tautan versi barunya, dan memuat ulang membuat
            // daftarnya berkedip kosong sesaat setelah sheet menutup.
            //
            // Album dan asetnya DIPERTAHANKAN kalau respons PATCH tidak
            // menyertakannya — endpoint sunting tidak menjanjikan relasi itu ikut
            // dikirim, dan menimpanya dengan nil membuat barisnya kehilangan
            // thumbnail dan nama tepat setelah disimpan.
            var merged = updated
            if merged.album == nil { merged.album = links[index].album }
            if merged.assets == nil { merged.assets = links[index].assets }
            links[index] = merged
            return nil
        } catch {
            return message(for: error, fallback: "Failed to update link")
        }
    }

    /// - Returns: pesan kesalahan, atau nil kalau berhasil.
    func delete(_ id: String) async -> String? {
        do {
            try await repo.delete(id)
            links.removeAll { $0.id == id }
            return nil
        } catch {
            return message(for: error, fallback: "Failed to delete link")
        }
    }

    /// Terbaru dulu. Server tidak menjanjikan urutan apa pun, dan tautan yang
    /// baru dibuat itulah yang paling mungkin sedang dicari.
    private func fetch() async throws -> [SharedLinkDTO] {
        try await repo.all().sorted {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }
    }

    private func message(for error: Error, fallback: String.LocalizationValue) -> String {
        (error as? APIError)?.errorDescription ?? String(localized: fallback)
    }
}
