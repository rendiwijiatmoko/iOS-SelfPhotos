import SwiftUI

/// "Delete from Device" — satu perilaku, dipakai semua grid.
///
/// Dijadikan komponen karena tiga grid membangun context menu-nya sendiri-
/// sendiri (Photos, koleksi, hasil pencarian), dan menyalin aturannya ke tiga
/// tempat berarti tiga kesempatan untuk menyimpang. Yang paling mudah menyimpang
/// justru bagian yang paling berbahaya: SIAPA yang boleh dihapus.
enum DeviceCopyDeletion {
    /// nil kalau foto ini tidak boleh dihapus dari perangkat.
    ///
    /// Hanya untuk yang ada di DUA tempat. Foto yang cuma ada di perangkat
    /// dihapus lewat "Delete" biasa — menawarkannya di sini akan membuat
    /// penghapusan satu-satunya salinan terlihat seperti pembersihan ruang
    /// penyimpanan.
    static func menuAction(
        for asset: AssetLite, request: @escaping (String) -> Void
    ) -> PhotoGridMenuAction? {
        guard asset.origin == .both else { return nil }
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
        let localID = LocalPhotoLibrary.isLocal(id)
            ? LocalPhotoLibrary.localIdentifier(from: id)
            : manager.localIdentifier(forServerAsset: id)

        guard let localID else { return false }
        guard await LocalPhotoLibrary.shared.delete(
            [LocalPhotoLibrary.assetID(for: localID)]) else { return false }

        // Tautannya DIPUTUS, catatan unggahannya tidak.
        //
        // Asetnya tetap ada di server dan tetap tidak boleh diunggah ulang —
        // yang tidak berlaku lagi hanya "ada salinannya di perangkat ini".
        // Menghapus catatannya sekalian akan membuat fotonya naik lagi pada
        // putaran pencadangan berikutnya.
        try? manager.unlinkDeviceAsset(localIdentifier: localID)
        return true
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
