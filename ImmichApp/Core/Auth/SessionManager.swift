import Foundation
import Observation

@MainActor
@Observable
class SessionManager {
    enum AuthMode: String { case bearer, apiKey }

    private(set) var baseURL: URL?
    private(set) var currentUser: UserResponseDTO?
    var isLoggedIn: Bool = false

    private var serverInput: String?
    private var token: String?
    private var mode: AuthMode = .bearer

    var authHeaders: [String: String] {
        guard let token else { return [:] }
        return mode == .bearer ? ["Authorization": "Bearer \(token)"]
                               : ["x-api-key": token]
    }

    /// Snapshot untuk APIClient yang berjalan di luar main actor.
    var requestContext: (baseURL: URL?, authHeaders: [String: String]) {
        (baseURL, authHeaders)
    }

    /// Cuplikan yang bisa dibaca dari thread mana pun.
    ///
    /// Diperbarui hanya saat server atau token berubah — kejadian yang bisa
    /// dihitung dengan jari sepanjang satu sesi. Tanpa ini, setiap permintaan
    /// jaringan harus melompat ke main actor hanya untuk membaca dua nilai yang
    /// nyaris tidak pernah berubah.
    private(set) var snapshot: (baseURL: URL?, authHeaders: [String: String]) = (nil, [:])

    private func refreshSnapshot() {
        snapshot = (baseURL, authHeaders)
    }

    /// Klien khusus gambar, dibuat sekali.
    @ObservationIgnored lazy var imageAPI = APIClient(
        session: self,
        urlSession: URLSession(configuration: APIClient.imageSessionConfiguration))

    @ObservationIgnored private lazy var api = APIClient(session: self)

    init() {
        loadStoredSession()
    }

    /// Sesi tersimpan dibaca SECARA SINKRON di init, bukan menunggu `restore()`.
    ///
    /// `restore()` berjalan asinkron dan menunggu jawaban server. Selama itu
    /// `isLoggedIn` masih false, jadi router sempat menampilkan halaman masuk
    /// lalu berpindah sendiri ke Photos begitu jawabannya datang — kedipan yang
    /// terlihat setiap kali aplikasi dibuka.
    ///
    /// Keychain sudah cukup untuk tahu pernah ada sesi; keabsahannya diperiksa
    /// belakangan oleh `restore()`.
    private func loadStoredSession() {
        guard var server = KeychainStore.read("serverURL"),
              let token = KeychainStore.read("token"),
              let mode = KeychainStore.read("mode").flatMap(AuthMode.init)
        else { return }

        // Entri lama menyimpan URL yang sudah berakhiran /api.
        if server.hasSuffix("/api") { server.removeLast(4) }
        try? setServer(server)
        applyAuth(token: token, mode: mode)
        isLoggedIn = true
        // Profil ikut dipulihkan di sini, dengan alasan yang sama seperti
        // sesinya: supaya avatar tidak memulai sebagai "?" tiap peluncuran.
        loadStoredUser()
    }

    func setServer(_ raw: String) throws {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if !s.hasPrefix("http") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s + "/api") else { throw APIError.invalidURL }
        serverInput = s
        baseURL = url
        refreshSnapshot()
    }

    func ping() async throws { let _: ServerPingDTO = try await api.send(.init(path: "/server/ping")) }
    func features() async throws -> ServerFeaturesDTO { try await api.send(.init(path: "/server/features")) }

    func loginPassword(email: String, password: String) async throws {
        let ep = Endpoint.json("/auth/login", method: .post,
                               body: LoginRequestDTO(email: email, password: password))
        let res: LoginResponseDTO = try await api.send(ep)
        applyAuth(token: res.accessToken, mode: .bearer)
        try await fetchMe()
        persist()
        isLoggedIn = true
    }

    func loginApiKey(_ key: String) async throws {
        applyAuth(token: key, mode: .apiKey)
        try await fetchMe()
        persist()
        isLoggedIn = true
    }

    private func fetchMe() async throws {
        let user: UserResponseDTO = try await api.send(.init(path: "/users/me"))
        currentUser = user
        storeUser(user)
    }

    // MARK: - Profil tersimpan

    private static let userKey = "session.currentUser"

    /// Profil disimpan di perangkat dan dibaca kembali di `init`.
    ///
    /// Tanpa ini, avatar di toolbar memulai setiap peluncuran sebagai "?" lalu
    /// berganti sendiri begitu `/users/me` menjawab — dan fotonya, yang byte-nya
    /// sebenarnya sudah ada di cache disk, tidak bisa dicari karena kunci
    /// cache-nya ikut hilang bersama profilnya.
    ///
    /// Bukan rahasia, jadi UserDefaults; token tetap di Keychain.
    private func storeUser(_ user: UserResponseDTO) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        UserDefaults.standard.set(data, forKey: Self.userKey)
    }

    private func loadStoredUser() {
        guard let data = UserDefaults.standard.data(forKey: Self.userKey),
              let user = try? JSONDecoder().decode(UserResponseDTO.self, from: data)
        else { return }
        currentUser = user
    }

    /// Memeriksa sesi yang sudah dipulihkan di init dan mengisi data pengguna.
    ///
    /// Hanya penolakan TEGAS dari server yang mengeluarkan pengguna. Gagal karena
    /// jaringan tidak: sesinya mungkin masih sah, dan memaksa masuk ulang setiap
    /// kali sinyal hilang jelas bukan yang diinginkan.
    func restore() async {
        guard isLoggedIn else { return }
        do {
            try await validate()
            try await fetchMe()
        } catch APIError.unauthorized {
            logout()
        } catch {
            // Offline: sesi tersimpan tetap dipakai.
        }
    }

    private func validate() async throws { try await api.sendVoid(.init(path: "/auth/validateToken", method: .post)) }

    /// Mengambil ulang data pengguna dari server, diam-diam.
    ///
    /// Dipanggil setiap kali Library dan sheet pengaturan dibuka: inilah cara
    /// aplikasi tahu foto profilnya sudah diganti di server. Penanda
    /// perubahannya ikut berganti, kunci cache avatarnya ikut berganti, dan
    /// hanya pada saat itulah gambarnya diunduh lagi — sisa waktunya jawabannya
    /// sama persis dan avatar tetap dijawab dari cache.
    ///
    /// Kegagalan DIABAIKAN: ini penyegaran latar, dan data yang sudah ada masih
    /// benar sampai jawaban baru datang.
    func refreshUser() async {
        guard isLoggedIn, !isRefreshingUser else { return }
        isRefreshingUser = true
        defer { isRefreshingUser = false }
        try? await fetchMe()
    }

    /// Penjaga supaya dua layar yang muncul berbarengan tidak menembak
    /// `/users/me` dua kali. Sengaja tidak diamati: ini pembukuan internal.
    @ObservationIgnored private var isRefreshingUser = false

    func logout() {
        // Snapshot header sebelum token dihapus supaya request logout tetap terautentikasi.
        let headers = authHeaders
        Task { try? await api.sendVoid(.init(path: "/auth/logout", method: .post, extraHeaders: headers)) }
        token = nil; currentUser = nil; isLoggedIn = false
        // Sampul album yang sudah diselesaikan menyimpan id aset milik akun
        // lama; membawanya ke akun berikutnya berarti permintaan gambar yang
        // pasti ditolak.
        AlbumCoverStore.shared.clear()
        // Potret album, orang, favorit, arsip, dan sampah ikut dibuang dengan
        // alasan yang lebih keras lagi: itu bukan sekadar data basi, itu isi
        // perpustakaan orang lain yang akan tergambar di layar akun berikutnya
        // sebelum server sempat membantahnya.
        LocalSnapshot.clearAll()
        refreshSnapshot()
        UserDefaults.standard.removeObject(forKey: Self.userKey)
        ["serverURL", "token", "mode"].forEach(KeychainStore.delete)
    }

    private func applyAuth(token: String, mode: AuthMode) {
        self.token = token
        self.mode = mode
        refreshSnapshot()
    }
    private func persist() {
        if let serverInput { KeychainStore.save(serverInput, for: "serverURL") }
        if let token { KeychainStore.save(token, for: "token") }
        KeychainStore.save(mode.rawValue, for: "mode")
    }
}
