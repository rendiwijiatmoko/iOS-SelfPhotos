import Foundation
import Observation

private extension String {
    var normalizedVersion: String {
        hasPrefix("v") ? String(dropFirst()) : self
    }
}

@MainActor
@Observable
final class SettingsViewModel {
    var storage: ServerStorageDTO?
    var serverInfo: ServerAboutDTO?
    var assetStats: AssetStatsDTO?
    var latestVersion: String?
    var cacheSize = 0

    /// Fase yang HANYA menyangkut data server.
    ///
    /// Dulu satu fase ini menutupi seluruh layar dengan spinner. Padahal
    /// sebagian besar isi pengaturan sudah ada di perangkat ini — tema, jumlah
    /// kolom, ukuran cache, versi aplikasi, alamat server, keluar akun — dan
    /// tidak menunggu siapa pun. Menahannya di belakang satu permintaan jaringan
    /// berarti pengaturan yang seharusnya bisa dipakai offline pun ikut tidak
    /// bisa dibuka saat servernya tidak terjangkau.
    ///
    /// Sekarang penantiannya tinggal di bagian yang memang datang dari server:
    /// penyimpanan, jumlah aset, dan versi server.
    var serverPhase: LoadingPhase<Void> = .idle

    // Preferensi tampilan disimpan lokal — API Immich tidak punya
    // preferensi theme/grid, dulu app salah mengirimnya ke server.
    static let themeKey = "settings.theme"
    static let gridColumnsKey = "settings.gridColumns"

    var selectedTheme: String
    var gridColumns: Int

    private let repo: SettingsRepository

    init(repo: SettingsRepository) {
        self.repo = repo
        selectedTheme = UserDefaults.standard.string(forKey: Self.themeKey) ?? "system"
        let stored = UserDefaults.standard.integer(forKey: Self.gridColumnsKey)
        gridColumns = stored > 0 ? stored : 3
    }

    /// Nama dan email penggunanya TIDAK diambil di sini — `SessionManager` sudah
    /// memegangnya sejak masuk, dan menyegarkannya adalah urusan
    /// `SessionManager.refreshUser()`. Menariknya lagi di sini hanya berarti dua
    /// permintaan `/users/me` untuk satu layar yang sama.
    func loadServerInfo() async {
        serverPhase = .loading
        do {
            async let storageTask = repo.getStorageInfo()
            async let serverTask = repo.getServerInfo()
            // Jumlah aset dibiarkan gagal diam-diam: header masih berguna tanpa
            // angka itu, sedangkan menjatuhkan seluruh bagian server karena satu
            // hitungan tidak.
            async let statsTask = try? repo.getAssetStats()
            // Sama: pemeriksaan versi bisa dimatikan di server, dan itu bukan
            // alasan untuk menandai datanya gagal.
            async let versionTask = try? repo.getVersionCheck()

            let (storage, server) = try await (storageTask, serverTask)

            self.storage = storage
            self.serverInfo = server
            self.assetStats = await statsTask
            self.latestVersion = await versionTask?.releaseVersion

            serverPhase = .loaded(())
        } catch {
            serverPhase = .failed(
                (error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Versi aplikasi ini, dari Info.plist.
    var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    /// Perbandingan dilakukan setelah membuang awalan "v".
    ///
    /// Server mengirim tag rilis apa adanya ("v1.130.0") sementara `/server/about`
    /// mengirim versinya tanpa awalan — tanpa dinormalkan, keduanya tidak pernah
    /// dianggap sama dan pembaruan seolah selalu tersedia.
    var isUpdateAvailable: Bool {
        guard let latest = latestVersion?.normalizedVersion,
              let current = serverInfo?.version.normalizedVersion
        else { return false }
        return latest != current
    }

    func refreshCacheSize() async {
        cacheSize = await ImageCache.shared.diskCacheSize()
    }

    func clearCache() async {
        await ImageCache.shared.clear()
        await refreshCacheSize()
    }

    func updateTheme(_ theme: String) {
        selectedTheme = theme
        UserDefaults.standard.set(theme, forKey: Self.themeKey)
    }

    func updateGridColumns(_ columns: Int) {
        gridColumns = columns
        UserDefaults.standard.set(columns, forKey: Self.gridColumnsKey)
    }
}
