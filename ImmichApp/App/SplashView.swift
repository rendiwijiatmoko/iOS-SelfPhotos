import SwiftUI

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

            Image(systemName: "photo.stack.fill")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    SplashView()
}
