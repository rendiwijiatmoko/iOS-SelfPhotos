import Foundation
import SwiftUI

/// Kabar kegagalan yang lewat sendiri, bukan yang harus ditutup.
///
/// **Kenapa bukan alert.** Alert menuntut jawaban untuk sesuatu yang tidak punya
/// pilihan: "Action Failed / OK". Satu-satunya yang bisa dilakukan pengguna
/// adalah mengakui bahwa ia sudah membacanya — dan sampai ia melakukannya, layar
/// di belakangnya beku. Di layar detail aset itu terasa berkali lipat lebih
/// buruk, karena kegagalannya justru paling sering datang beruntun: setiap
/// geseran foto saat offline adalah satu permintaan baru yang gagal.
///
/// Toast membalik hubungannya. Kabar itu muncul, terbaca, lalu pergi — dan foto
/// di belakangnya tidak pernah berhenti bisa digeser.
struct ErrorToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                // Dua baris: pesan server bisa panjang, tapi toast yang tumbuh
                // sampai separuh layar bukan toast lagi.
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: .capsule)
        .overlay { Capsule().strokeBorder(.separator, lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal, 24)
    }
}

/// Satu KEJADIAN gagal, bukan sekadar teksnya.
///
/// Identitasnya yang penting. Kegagalan beruntun hampir selalu berbunyi sama —
/// "No internet connection." dua kali adalah dua kejadian, bukan satu — dan
/// pengamat perubahan apa pun (`onChange`, `task(id:)`) tidak berjalan untuk
/// nilai yang identik. Tanpa identitas, ketukan kedua tidak bergetar dan
/// hitungan mundurnya tidak dimulai ulang: toast-nya bisa hilang seketika
/// setelah kegagalan yang barusan.
struct ErrorEvent: Equatable {
    let id = UUID()
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

/// Menampilkan `event` sebagai toast, lalu mengosongkannya sendiri.
///
/// Kejadiannya sendiri yang jadi binding, bukan pasangan bool + teks: dengan
/// begitu pemanggil cukup menulis satu tempat — dan "ada kabar" tidak bisa lagi
/// menyimpang dari "toast-nya tampil".
private struct ErrorToastModifier: ViewModifier {
    @Binding var event: ErrorEvent?
    let duration: Duration

    /// Naik setiap toast baru muncul; ini pemicu getarnya.
    @State private var appearances = 0
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let event {
                    ErrorToast(message: event.message)
                        // Toast tidak boleh MENELAN sentuhan. Ia menempati
                        // bagian bawah layar — tempat strip thumbnail berada di
                        // layar detail — dan selama dua setengah detik itu
                        // ketukan di sana tidak akan sampai ke tujuannya.
                        .allowsHitTesting(false)
                        // Dari bawah, sejalan dengan arah munculnya — dan
                        // `combined(with: .opacity)` supaya perginya tidak
                        // terlihat seperti tersentak keluar layar.
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 24)
                }
            }
            .animation(.snappy(duration: 0.25), value: event)
            .sensoryFeedback(.error, trigger: appearances)
            .onChange(of: event) { _, newValue in
                dismissTask?.cancel()
                guard newValue != nil else { return }
                appearances &+= 1
                dismissTask = Task {
                    try? await Task.sleep(for: duration)
                    guard !Task.isCancelled else { return }
                    event = nil
                }
            }
            // Toast yang masih menghitung mundur saat layarnya ditutup akan
            // mengosongkan pesan milik layar berikutnya.
            .onDisappear { dismissTask?.cancel() }
    }
}

extension View {
    /// - Parameter duration: cukup lama untuk dibaca, cukup singkat untuk tidak
    ///   menghalangi. Dua setengah detik untuk satu kalimat pendek.
    func errorToast(
        _ event: Binding<ErrorEvent?>,
        duration: Duration = .seconds(2.5)
    ) -> some View {
        modifier(ErrorToastModifier(event: event, duration: duration))
    }
}
