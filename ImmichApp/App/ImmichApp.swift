import SwiftUI
import UIKit

/// Ada HANYA untuk satu panggilan yang tidak punya padanan di SwiftUI.
///
/// Saat transfer latar selesai sementara aplikasinya sudah tidak berjalan,
/// sistem meluncurkannya kembali dan memanggil metode di bawah. SwiftUI tidak
/// menyediakan jalur untuk itu — `.onOpenURL`, `.backgroundTask`, dan
/// `scenePhase` semuanya tentang hal lain. Jadi delegate-nya dipasang kembali,
/// seminimal mungkin.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackupUploader.sessionIdentifier else {
            completionHandler()
            return
        }
        // Disimpan, BUKAN dipanggil sekarang. iOS menuntutnya dipanggil setelah
        // semua delegate selesai menyampaikan hasilnya — memanggilnya lebih awal
        // berarti melapor siap sebelum catatannya tertulis.
        // Tanpa pembungkus `Task`: `UIApplicationDelegate` sudah terikat main
        // actor, jadi menundanya satu giliran hanya membuka jeda tempat sesi
        // latar bisa lebih dulu memanggil `urlSessionDidFinishEvents` dan
        // menemukan handler-nya masih nil.
        BackupUploader.shared.backgroundCompletion = completionHandler
        BackupUploader.shared.reconnect()
    }
}

@main
struct ImmichApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = SessionManager()

    init() {
        // Pendaftaran tugas latar harus terjadi SEBELUM peluncuran selesai.
        // `BGTaskScheduler` menegakkan itu dengan keras: mendaftar belakangan
        // menjatuhkan aplikasinya, bukan sekadar gagal.
        BackupScheduler.register()
    }

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environment(session)
                .task { await session.restore() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        // INILAH tulang punggung pencadangan di iOS, bukan tugas
                        // latarnya. Yang benar-benar bisa diandalkan adalah saat
                        // pengguna membuka aplikasinya sendiri; sisanya bonus.
                        BackupService.shared.configure(session: session)
                        // Menyambung kembali ke transfer yang mungkin masih
                        // berjalan sejak sesi sebelumnya — sistem menyimpannya,
                        // dan tanpa ini hasilnya tidak pernah terbaca.
                        BackupUploader.shared.reconnect()
                        guard BackupService.shared.isEnabled else { return }
                        Task {
                            await BackupService.shared.prepare()
                            BackupService.shared.start()
                        }
                    case .background:
                        BackupScheduler.schedule()
                    default:
                        break
                    }
                }
        }
    }
}
