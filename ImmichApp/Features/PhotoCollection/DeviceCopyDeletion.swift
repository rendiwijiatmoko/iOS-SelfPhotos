import SwiftUI

/// "Delete from Device" — satu perilaku, dipakai semua grid.
///
/// Dijadikan komponen karena tiga grid membangun context menu-nya sendiri-
/// sendiri (Photos, koleksi, hasil pencarian), dan menyalin aturannya ke tiga
/// tempat berarti tiga kesempatan untuk menyimpang. Yang paling mudah menyimpang
/// justru bagian yang paling berbahaya: SIAPA yang boleh dihapus.
enum DeviceCopyDeletion {
    /// Menerjemahkan isi grid menjadi id PhotoKit yang benar-benar masih ada.
    ///
    /// Mode Select dapat berisi campuran petak lokal yang sudah dicadangkan
    /// (`device:` dengan origin `.both`), petak server yang punya pasangan
    /// lokal, petak lokal yang belum aman, dan petak server-only. Hanya dua
    /// kelompok pertama yang boleh sampai ke permintaan hapus PhotoKit.
    @MainActor
    static func localIdentifiers(for assets: [AssetLite]) -> [String] {
        let manager = SwiftDataManager.shared
        var candidates: [String] = []
        var seen = Set<String>()
        candidates.reserveCapacity(assets.count)

        // Tetap pertahankan pagar yang sama dengan aksi satu item: jangan
        // menawarkan pembersihan perangkat untuk satu-satunya salinan yang
        // belum pernah berhasil masuk server.
        for asset in assets where asset.origin == .both {
            let localID = localIdentifier(for: asset.id, manager: manager)
            guard let localID, seen.insert(localID).inserted else { continue }
            candidates.append(localID)
        }

        let existing = LocalPhotoLibrary.existingLocalIdentifiers(candidates)
        return candidates.filter(existing.contains)
    }

    /// Mengecek salinan yang benar-benar masih dikenal PhotoKit.
    ///
    /// `origin` dan `BackupRecord` adalah cache untuk menggambar cepat. Keduanya
    /// dapat tertinggal ketika foto dihapus dari Photos atau aplikasi lain, jadi
    /// tidak boleh menjadi satu-satunya dasar untuk menawarkan aksi destruktif.
    @MainActor
    static func hasDeviceCopy(for asset: AssetLite) -> Bool {
        guard asset.isOnDevice else { return false }

        let localID: String?
        if LocalPhotoLibrary.isLocal(asset.id) {
            localID = LocalPhotoLibrary.localIdentifier(from: asset.id)
        } else {
            localID = SwiftDataManager.shared.localIdentifier(forServerAsset: asset.id)
        }

        guard let localID else { return false }
        return LocalPhotoLibrary.assetExists(localID)
    }

    /// nil kalau foto ini tidak boleh dihapus dari perangkat.
    ///
    /// Hanya untuk yang ada di DUA tempat. Foto yang cuma ada di perangkat
    /// dihapus lewat "Delete" biasa — menawarkannya di sini akan membuat
    /// penghapusan satu-satunya salinan terlihat seperti pembersihan ruang
    /// penyimpanan.
    @MainActor
    static func menuAction(
        for asset: AssetLite, request: @escaping (String) -> Void
    ) -> PhotoGridMenuAction? {
        guard asset.origin == .both, hasDeviceCopy(for: asset) else { return nil }
        return PhotoGridMenuAction(
            title: String(localized: "Delete from Device"),
            systemImage: "iphone.slash",
            isDestructive: true
        ) {
            request(asset.id)
        }
    }

    /// Menghapus salinan perangkat, menyisakan yang di server.
    ///
    /// Petak berlencana "ada di keduanya" datang dari dua arah dengan jenis id
    /// yang berbeda: petak SERVER memakai id server, sedangkan foto yang baru
    /// diunggah masih berdiri sebagai petak LOKAL berawalan `device:` sampai
    /// sync membawa aset servernya. Keduanya harus berujung pada
    /// `PHAsset.localIdentifier` yang sama.
    ///
    /// - Returns: true kalau berkasnya benar-benar terhapus.
    @discardableResult
    @MainActor
    static func perform(_ id: String) async -> Bool {
        let manager = SwiftDataManager.shared
        guard let localID = localIdentifier(for: id, manager: manager),
              LocalPhotoLibrary.assetExists(localID)
        else { return false }
        return await perform(localIdentifiers: [localID]) == 1
    }

    /// Menghapus beberapa salinan lokal dalam satu transaksi PhotoKit.
    ///
    /// Daftar dicek ulang tepat sebelum penghapusan karena menu dapat tetap
    /// terbuka saat Photos diubah oleh app lain. Nilai kembali adalah jumlah
    /// yang benar-benar diminta untuk dihapus, bukan jumlah seluruh seleksi.
    @discardableResult
    @MainActor
    static func perform(localIdentifiers: [String]) async -> Int {
        let existing = LocalPhotoLibrary.existingLocalIdentifiers(localIdentifiers)
        guard !existing.isEmpty else { return 0 }

        let ids = existing.map { LocalPhotoLibrary.assetID(for: $0) }
        guard await LocalPhotoLibrary.shared.delete(ids) else { return 0 }

        // Tautannya DIPUTUS, catatan unggahannya tidak.
        //
        // Asetnya tetap ada di server dan tetap tidak boleh diunggah ulang —
        // yang tidak berlaku lagi hanya "ada salinannya di perangkat ini".
        // Menghapus catatannya sekalian akan membuat fotonya naik lagi pada
        // putaran pencadangan berikutnya.
        let manager = SwiftDataManager.shared
        for localID in existing {
            try? manager.unlinkDeviceAsset(localIdentifier: localID)
        }
        return existing.count
    }

    @MainActor
    private static func localIdentifier(
        for id: String,
        manager: SwiftDataManager
    ) -> String? {
        LocalPhotoLibrary.isLocal(id)
            ? LocalPhotoLibrary.localIdentifier(from: id)
            : manager.localIdentifier(forServerAsset: id)
    }
}

private struct DeviceCopyDeletionAlert: ViewModifier {
    @Binding var pendingID: String?
    var onDeleted: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            "Delete from Device",
            isPresented: Binding(
                get: { pendingID != nil },
                set: { if !$0 { pendingID = nil } }),
            presenting: pendingID
        ) { id in
            Button("Delete", role: .destructive) {
                pendingID = nil
                Task {
                    if await DeviceCopyDeletion.perform(id) { onDeleted() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            // Kalimatnya BERBEDA dari "Delete Photo", dan itu intinya.
            //
            // Yang dihapus bukan foto melainkan salah satu salinannya. "This
            // cannot be undone" akan membuat tindakan yang aman terdengar
            // seperti tindakan yang tidak bisa ditarik kembali.
            Text("The copy on this device will be removed. The photo stays on your server.")
        }
    }
}

extension View {
    /// - Parameter onDeleted: dipanggil hanya kalau berkasnya benar-benar
    ///   terhapus — untuk getaran dan penggambaran ulang.
    func deleteFromDeviceAlert(
        _ pendingID: Binding<String?>, onDeleted: @escaping () -> Void = {}
    ) -> some View {
        modifier(DeviceCopyDeletionAlert(pendingID: pendingID, onDeleted: onDeleted))
    }
}
