import SwiftUI

/// Foto profil pengguna, dengan inisial sebagai dasarnya.
///
/// Inisial SELALU digambar lebih dulu dan fotonya menimpa begitu ada. Immich
/// tidak mewajibkan pengguna punya foto profil, dan yang punya pun tidak selalu
/// fotonya sudah ada di perangkat ini — jadi tidak pernah ada petak abu-abu atau
/// ikon rusak di toolbar, cukup huruf yang berganti jadi foto.
///
/// Fotonya lewat `ImageCache` yang sama dengan seluruh gambar lain: sekali
/// diunduh, ia dijawab dari memori atau disk sampai penggunanya benar-benar
/// menggantinya di server (lihat `UserResponseDTO.profileImageCacheKey`).
@MainActor
struct ProfileAvatar: View {
    enum Style {
        /// Tombol kecil di toolbar Library.
        case toolbar
        /// Kepala besar di sheet pengaturan.
        case header
    }

    var style: Style = .toolbar

    @Environment(SessionManager.self) private var session
    /// Alasannya sama seperti di `AuthImage`: bitmap-nya milik cache, view ini
    /// hanya perlu digambar ulang saat pemuatannya selesai. Nilainya HARUS ikut
    /// dibaca di `body` supaya ketergantungannya benar-benar terbentuk.
    @State private var revision = 0

    var body: some View {
        let shown = cachedImage(revision: revision)

        return initialsCircle
            .overlay {
                if let shown {
                    Image(uiImage: shown)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(.circle)
//            .padding(.trailing, style == .toolbar ? Self.toolbarTrailingCompensation : 0)
            .task(id: cacheKey) { await load() }
    }

    // MARK: - Inisial

    /// Latarnya dipasang SESUDAH padding/frame, bukan langsung di teksnya:
    /// lingkarannya harus selebar bidang yang sudah diberi ruang, bukan selebar
    /// hurufnya.
    @ViewBuilder
    private var initialsCircle: some View {
        switch style {
        case .toolbar:
            // Ukuran TETAP, bukan `padding()` mengikuti hurufnya: dengan padding,
            // pengguna berinisial satu huruf mendapat lingkaran yang lebih sempit
            // daripada yang berinisial dua — bulatnya tidak pernah sama.
            Text(initials)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: Self.toolbarSide, height: Self.toolbarSide)
                .background(Self.gradient, in: .circle)
        case .header:
            Text(initials)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 116, height: 116)
                .background(Self.gradient, in: .circle)
        }
    }

    private static let toolbarSide: CGFloat = 42

    /// Ruang berlebih di kanan avatar yang harus ditarik balik.
    ///
    /// Item toolbar di iOS 26 tetap menyisakan inset untuk kapsul kacanya
    /// meskipun kapsulnya sendiri dimatikan lewat `sharedBackgroundVisibility`.
    /// Untuk tombol seukuran ikon inset itu tidak terasa; untuk lingkaran
    /// selebar ini, ia mendorong avatarnya menjorok jauh dari tepi kanan.
    ///
    /// Dipasang di sini, bukan di tiap pemakainya, supaya avatar di layar mana
    /// pun duduk di tempat yang sama.
    static let toolbarTrailingCompensation: CGFloat = -10

    private static let gradient = LinearGradient(
        colors: [.orange, .pink, .purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)

    private var initials: String {
        let name = session.currentUser?.name ?? "?"
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    // MARK: - Foto

    /// nil kalau penggunanya memang tidak punya foto profil — dan itu juga yang
    /// membuat `task` di bawah tidak mengunduh apa pun.
    private var cacheKey: String? {
        guard let user = session.currentUser, user.hasProfileImage else { return nil }
        return user.profileImageCacheKey
    }

    /// Sisi terpanjang yang benar-benar dibutuhkan di layar; avatar toolbar tidak
    /// perlu bitmap seukuran kepala di sheet pengaturan.
    private var pixelSize: Int {
        switch style {
        case .toolbar: 180
        case .header: 400
        }
    }

    /// Selalu dari cache, tidak pernah dari state view.
    ///
    /// - Parameter revision: isinya TIDAK dipakai — ia parameter supaya
    ///   pembacaannya terjadi di `body` dan tidak bisa hilang.
    private func cachedImage(revision: Int) -> UIImage? {
        guard let cacheKey else { return nil }
        return ImageMemoryCache.shared.image(
            for: ImageCache.memoryKey(cacheKey, pixelSize))
    }

    private func load() async {
        guard let user = session.currentUser, user.hasProfileImage else { return }

        let key = user.profileImageCacheKey
        // Sudah tergambar dari cache di `body`; tidak ada yang perlu dikerjakan.
        if ImageMemoryCache.shared.image(for: ImageCache.memoryKey(key, pixelSize)) != nil {
            return
        }

        let api = session.imageAPI
        let endpoint = Endpoint(path: "/users/\(user.id)/profile-image")

        _ = try? await ImageCache.shared.image(
            key: key,
            maxPixelSize: pixelSize,
            fetch: { try await api.rawData(endpoint) })

        // Gagal pun tidak apa-apa: inisialnya sudah di layar, dan menaikkan
        // penanda hanya menggambar ulang hal yang sama.
        revision &+= 1
    }
}

#Preview {
    VStack(spacing: 24) {
        ProfileAvatar(style: .toolbar)
        ProfileAvatar(style: .header)
    }
    .environment(SessionManager())
}
