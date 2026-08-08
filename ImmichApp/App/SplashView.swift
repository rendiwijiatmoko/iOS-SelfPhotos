import SwiftUI

/// Identitas visual yang sama untuk splash dan login. Palette memberi lapisan
/// SF Symbol warna berbeda; masing-masing lapisan memakai linear gradient agar
/// tetap hidup di light maupun dark mode tanpa aset bitmap terpisah.
struct ImmichTortoiseLogo: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "tortoise.fill")
            .font(.system(size: size, weight: .regular))
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                Color.primary,
                LinearGradient(
                    colors: [.cyan, .blue, .indigo],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)
//                LinearGradient(
//                    colors: [.orange, .pink, .purple],
//                    startPoint: .leading,
//                    endPoint: .trailing)
            )
    }
}

/// Layar pembuka selama cache lokal dibaca.
///
/// Bukan hiasan: membaca puluhan ribu baris dari SwiftData lalu
/// mengelompokkannya jadi bulan butuh sepersekian detik, dan tanpa penutup apa
/// pun itu terlihat sebagai layar kosong yang berkedip tepat setelah aplikasi
/// dibuka. Spinner pun salah tempat — tidak ada yang sedang diunduh; fotonya
/// sudah ada di perangkat.
struct SplashView: View {
    var body: some View {
        ZStack {
            // Warna latar sistem, bukan warna sendiri: dengan begitu ia menyatu
            // dengan layar peluncuran maupun layar pertama aplikasi, di terang
            // maupun gelap.
            Color(.systemBackground)
                .ignoresSafeArea()

            ImmichTortoiseLogo(size: 64)
                .symbolEffect(.pulse)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    SplashView()
}
