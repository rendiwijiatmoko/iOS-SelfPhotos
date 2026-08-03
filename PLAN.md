# Rencana Pembuatan Aplikasi Immich untuk iOS — SwiftUI + iOS 26

> **Dokumen ini ditulis untuk junior developer atau AI model yang lebih murah.**
> Arsitektur: **MVVM + async/await manual (URLSession)**. Detail: **sangat detail + kode skeleton**.
> Kerjakan **berurutan dari atas ke bawah**. Setiap fase punya: tujuan, endpoint API, kode skeleton yang bisa langsung disalin & dilengkapi, daftar tugas (checklist), dan acceptance criteria.
>
> Aturan main: kalau ada kode skeleton, **salin, pahami, lalu lengkapi bagian `// TODO`**. Jangan lompat fase. Test dengan server Immich asli sedini mungkin.

---

## Daftar Isi

- [0. Ringkasan & Asumsi](#0-ringkasan--asumsi)
- [1. Cara Kerja Immich API](#1-cara-kerja-immich-api-wajib-paham-dulu)
- [2. Arsitektur & Struktur Proyek](#2-arsitektur--struktur-proyek)
- [3. Tech Stack & Konvensi](#3-tech-stack--konvensi)
- [FASE 0 — Setup Proyek Xcode](#fase-0--setup-proyek-xcode)
- [FASE 1 — Networking Layer](#fase-1--networking-layer)
- [FASE 2 — Data Models (DTO)](#fase-2--data-models-dto)
- [FASE 3 — Onboarding (Server URL + Login)](#fase-3--onboarding-server-url--login)
- [FASE 4 — Timeline (Grid Foto Utama)](#fase-4--timeline-grid-foto-utama)
- [FASE 5 — Asset Detail (Viewer)](#fase-5--asset-detail-viewer-foto-full)
- [FASE 6 — Albums](#fase-6--albums)
- [FASE 7 — Search & Explore](#fase-7--search--explore)
- [FASE 8 — People / Faces](#fase-8--people--faces)
- [FASE 9 — Memories](#fase-9--memories)
- [FASE 10 — Backup / Upload](#fase-10--backup--upload-foto-dari-hp)
- [FASE 11 — Settings & Profil](#fase-11--settings--profil)
- [FASE 12 — Sync & Cache (SwiftData)](#fase-12--sinkronisasi--cache-lokal-swiftdata)
- [FASE 13 — Polish & Rilis](#fase-13--polish-aksesibilitas--rilis)
- [Testing, Urutan MVP, Lampiran](#strategi-testing-lakukan-di-setiap-fase)

---

## 0. Ringkasan & Asumsi

**Tujuan akhir:** Aplikasi iOS native untuk mengakses server [Immich](https://immich.app) pribadi. User bisa: login ke server sendiri → melihat semua foto dalam timeline → buka foto detail → lihat album → cari foto → lihat orang (face) → lihat memories → backup foto dari HP → atur setelan.

**Asumsi (ubah kalau salah):**

- Target minimum **iOS 26.0**, gunakan API terbaru (Swift 6 strict concurrency, `@Observable`, `NavigationStack`, `SwiftData`, desain *Liquid Glass*).
- Arsitektur **MVVM + Repository**, networking **URLSession + async/await manual** (tanpa Alamofire, tanpa generator OpenAPI).
- Satu user = satu server (multi-account = peningkatan nanti).
- Referensi API resmi: <https://api.immich.app/endpoints>. Sumber kebenaran per-server: `https://<server>/api/spec.json`.

**Prinsip kerja:**

1. Buat 1 fitur berjalan end-to-end sebelum pindah fitur lain.
2. Setiap endpoint dibungkus fungsi di layer networking — **jangan** panggil `URLSession` dari View.
3. Commit kecil per tugas. Contoh pesan: `feat(auth): login email/password`.
4. Ragu bentuk response? Cek Swagger server: `https://<server>/api/docs`.

---

## 1. Cara Kerja Immich API (wajib paham dulu)

Base URL API selalu diakhiri `/api`. Contoh: `https://foto.domainku.com/api`.

### Autentikasi
Dua cara yang kita pakai:

1. **Access Token** (hasil login email/password) → header `Authorization: Bearer <accessToken>`.
2. **API Key** (dibuat user di web Immich) → header `x-api-key: <key>`.

App mendukung keduanya. OAuth = opsional (Fase 3E).

### Format umum
- JSON untuk request/response.
- Tanggal **ISO 8601** (`2026-08-03T10:30:00.000Z`).
- ID berupa **UUID** (string).
- Upload asset memakai **multipart/form-data** (bukan JSON).

### Tabel endpoint inti
(Method + path relatif terhadap `/api`.)

| Grup | Endpoint | Fungsi di app |
|---|---|---|
| Auth | `POST /auth/login` | Login email/password |
| Auth | `POST /auth/logout` | Logout |
| Auth | `POST /auth/validateToken` | Cek token valid |
| Auth | `POST /oauth/authorize` / `POST /oauth/callback` | OAuth (opsional) |
| Server | `GET /server/ping` | Cek server (balas `{"res":"pong"}`) |
| Server | `GET /server/about` / `GET /server/version` | Info versi |
| Server | `GET /server/features` | Fitur aktif (smartSearch, oauth, dll) |
| Server | `GET /server/config` | Config publik |
| Server | `GET /server/storage` | Info penyimpanan |
| User | `GET /users/me` | Profil user login |
| User | `GET /users/me/preferences` | Preferensi user |
| Timeline | `GET /timeline/buckets` | Daftar bucket waktu (per bulan) |
| Timeline | `GET /timeline/bucket` | Isi asset di satu bucket |
| Asset | `GET /assets/{id}` | Detail asset + EXIF |
| Asset | `GET /assets/{id}/thumbnail` | Thumbnail (`size=thumbnail\|preview`) |
| Asset | `GET /assets/{id}/original` | File original |
| Asset | `POST /assets` | Upload asset (multipart) |
| Asset | `POST /assets/bulk-upload-check` | Cek duplikat sebelum upload |
| Asset | `PUT /assets/{id}` | Update 1 asset (favorite/archive) |
| Asset | `PUT /assets` | Update banyak asset |
| Asset | `DELETE /assets` | Hapus (ke trash) |
| Album | `GET /albums` | Daftar album |
| Album | `GET /albums/{id}` | Detail album + asset |
| Album | `POST /albums` | Buat album |
| Album | `PUT /albums/{id}/assets` | Tambah asset |
| Album | `DELETE /albums/{id}/assets` | Hapus asset dari album |
| Search | `POST /search/metadata` | Cari metadata |
| Search | `POST /search/smart` | Cari cerdas (CLIP/teks bebas) |
| Search | `GET /search/explore` | Data Explore |
| Search | `GET /search/suggestions` | Saran filter |
| People | `GET /people` | Daftar orang |
| People | `GET /people/{id}` | Detail orang |
| People | `GET /people/{id}/thumbnail` | Foto wajah |
| People | `PUT /people/{id}` | Rename / sembunyikan |
| Memory | `GET /memories` | Memories |
| Download | `GET /download/asset/{id}` | Download asset |
| Sync | `POST /sync/full-sync` | Sinkron penuh |
| Sync | `POST /sync/delta-sync` | Sinkron perubahan |

> **Konsep Timeline (WAJIB):** Immich tidak mengirim semua foto sekaligus. `GET /timeline/buckets` → daftar bulan + jumlah foto. Lalu `GET /timeline/bucket?timeBucket=<bulan>` → asset di bulan itu. Ini yang bikin scroll ribuan foto tetap cepat. Pahami sebelum Fase 4.

---

## 2. Arsitektur & Struktur Proyek

```
ImmichIOS/
├── App/
│   ├── ImmichApp.swift              // @main
│   └── AppRouter.swift              // login vs main tab
├── Core/
│   ├── Networking/
│   │   ├── APIClient.swift
│   │   ├── Endpoint.swift
│   │   ├── APIError.swift
│   │   └── ImageLoader.swift        // loader gambar ber-auth
│   ├── Storage/
│   │   ├── KeychainStore.swift
│   │   └── AppSettings.swift
│   ├── Auth/
│   │   └── SessionManager.swift     // @Observable, sumber baseURL + token
│   └── Extensions/
├── Models/
│   ├── DTO/                         // struct match JSON API
│   └── Domain/                      // model bersih untuk UI
├── Features/
│   ├── Onboarding/  { View + ViewModel }
│   ├── Timeline/
│   ├── AssetDetail/
│   ├── Albums/
│   ├── Search/
│   ├── People/
│   ├── Memories/
│   ├── Backup/
│   └── Settings/
├── DesignSystem/
└── Resources/                       // Assets.xcassets, Localizable
```

**Aturan lapisan:**
- **View** (SwiftUI) → hanya tampilan + panggil ViewModel.
- **ViewModel** (`@Observable`) → state (`phase`, `items`), panggil Repository.
- **Repository** → panggil `APIClient`, ubah DTO → Domain.
- **APIClient** → satu-satunya tempat `URLSession`.

Alur data:
```
View → ViewModel → Repository → APIClient → URLSession → Server
                                    ↑
                              SessionManager (baseURL + auth header)
                                    ↑
                              KeychainStore (token, aman)
```

**Pola state ViewModel yang dipakai di seluruh app** (salin sekali, pakai di semua fitur):
```swift
enum LoadingPhase<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)   // pesan error untuk user
}
```

---

## 3. Tech Stack & Konvensi

- **Swift 6**, strict concurrency (`SWIFT_VERSION = 6`).
- **SwiftUI** + `NavigationStack`.
- **Observation** (`@Observable`, `@Bindable`) — bukan `ObservableObject`/`@Published`.
- **SwiftData** untuk cache (mulai Fase 12).
- **Keychain** untuk token & server URL (JANGAN UserDefaults untuk token).
- **async/await** untuk semua jaringan.
- **PhotosUI + Photos** untuk backup (Fase 10).
- ViewModel & UI di-anotasi `@MainActor`. Repository/APIClient boleh non-isolated (aman untuk concurrency).

Penamaan: `TimelineView.swift`, `TimelineViewModel.swift`, DTO diakhiri `DTO`.

**Bahasa string UI (PENTING):** semua label & pesan yang tampil ke user ditulis **default dalam Bahasa Inggris** dulu. Localization (termasuk Bahasa Indonesia) ditambahkan **nanti** di Fase 13. Aturan praktis sekarang:
- Tulis semua string user-facing dalam English, tapi **selalu** bungkus dengan `String(localized:)` sejak awal, contoh: `Text(String(localized: "Photos"))` atau langsung `Text("Photos")` (SwiftUI otomatis memperlakukan string literal sebagai `LocalizedStringKey`).
- Jangan hardcode Bahasa Indonesia di kode. Terjemahan ID dimasukkan lewat String Catalog (`Localizable.xcstrings`) di Fase 13, tanpa mengubah kode.
- Pesan error dari `APIError` juga English by default (lihat Fase 1).

---

## FASE 0 — Setup Proyek Xcode

**Tujuan:** Proyek kosong bisa di-build & jalan di simulator iOS 26.

**Tugas:**
- [ ] 0.1 New Project → iOS App, SwiftUI, Swift, Storage **None**.
- [ ] 0.2 Minimum Deployment = **iOS 26.0**; Swift Language Version = **6**.
- [ ] 0.3 Buat group folder sesuai Bagian 2.
- [ ] 0.4 Tambah `LoadingPhase` (Bagian 2) di `Core/`.
- [ ] 0.5 `.gitignore` Xcode (abaikan `xcuserdata`, `DerivedData`). Commit awal.

**Skeleton entry point:**
```swift
// App/ImmichApp.swift
import SwiftUI

@main
struct ImmichApp: App {
    @State private var session = SessionManager()   // dibuat di Fase 3

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environment(session)
                .task { await session.restore() }    // auto-login dari Keychain
        }
    }
}

// App/AppRouter.swift
import SwiftUI

struct AppRouter: View {
    @Environment(SessionManager.self) private var session
    var body: some View {
        if session.isLoggedIn {
            MainTabView()          // Fase 4+
        } else {
            OnboardingView()       // Fase 3
        }
    }
}
```

**Acceptance:** App jalan di simulator, tanpa warning concurrency.

---

## FASE 1 — Networking Layer

**Tujuan:** Bisa memanggil endpoint apa pun dengan aman, token otomatis, error tertangani.

**Tugas:**
- [ ] 1.1 `APIError.swift`.
- [ ] 1.2 `Endpoint.swift`.
- [ ] 1.3 `APIClient.swift` (send generic + sendVoid + upload multipart).
- [ ] 1.4 Unit test dengan `URLProtocol` mock (opsional tapi disarankan).

**Skeleton:**
```swift
// Core/Networking/APIError.swift
enum APIError: Error, LocalizedError {
    case invalidURL
    case notConnected
    case unauthorized
    case decoding(Error)
    case server(status: Int, message: String?)
    case unknown

    // Default English; localization ditambahkan di Fase 13 via String Catalog.
    var errorDescription: String? {
        switch self {
        case .invalidURL:      return String(localized: "Invalid server address.")
        case .notConnected:    return String(localized: "No internet connection.")
        case .unauthorized:    return String(localized: "Session expired, please sign in again.")
        case .decoding:        return String(localized: "Failed to read data from server.")
        case .server(_, let m):return m ?? String(localized: "A server error occurred.")
        case .unknown:         return String(localized: "An unknown error occurred.")
        }
    }
}
```
```swift
// Core/Networking/Endpoint.swift
import Foundation

enum HTTPMethod: String { case get = "GET", post = "POST", put = "PUT", delete = "DELETE" }

struct Endpoint {
    var path: String                       // contoh: "/timeline/buckets"
    var method: HTTPMethod = .get
    var query: [URLQueryItem] = []
    var body: Data? = nil
    var extraHeaders: [String: String] = [:]

    // helper agar gampang bikin body JSON
    static func json<T: Encodable>(_ path: String, method: HTTPMethod, body: T) -> Endpoint {
        let data = try? JSONEncoder.immich.encode(body)
        return Endpoint(path: path, method: method, body: data)
    }
}
```
```swift
// Core/Networking/APIClient.swift
import Foundation

final class APIClient {
    private let session: SessionManager
    private let urlSession: URLSession

    init(session: SessionManager, urlSession: URLSession = .shared) {
        self.session = session
        self.urlSession = urlSession
    }

    func send<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let (data, http) = try await perform(endpoint)
        try validate(http, data)
        do { return try JSONDecoder.immich.decode(T.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    func sendVoid(_ endpoint: Endpoint) async throws {
        let (data, http) = try await perform(endpoint)
        try validate(http, data)
    }

    // dipakai untuk gambar/original
    func rawData(_ endpoint: Endpoint) async throws -> Data {
        let (data, http) = try await perform(endpoint)
        try validate(http, data)
        return data
    }

    private func perform(_ endpoint: Endpoint) async throws -> (Data, HTTPURLResponse) {
        guard let baseURL = session.baseURL else { throw APIError.invalidURL }
        var comps = URLComponents(url: baseURL.appendingPathComponent(endpoint.path),
                                  resolvingAgainstBaseURL: false)
        if !endpoint.query.isEmpty { comps?.queryItems = endpoint.query }
        guard let url = comps?.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = endpoint.method.rawValue
        req.httpBody = endpoint.body
        if endpoint.body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (k, v) in session.authHeaders { req.setValue(v, forHTTPHeaderField: k) }
        for (k, v) in endpoint.extraHeaders { req.setValue(v, forHTTPHeaderField: k) }

        do {
            let (data, resp) = try await urlSession.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw APIError.unknown }
            return (data, http)
        } catch let e as URLError where e.code == .notConnectedToInternet {
            throw APIError.notConnected
        }
    }

    private func validate(_ http: HTTPURLResponse, _ data: Data) throws {
        switch http.statusCode {
        case 200..<300: return
        case 401:       throw APIError.unauthorized
        default:
            let msg = (try? JSONDecoder().decode(ServerErrorDTO.self, from: data))?.message
            throw APIError.server(status: http.statusCode, message: msg)
        }
    }
}

struct ServerErrorDTO: Decodable { let message: String? }

extension JSONDecoder {
    static let immich: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601   // catatan: aktifkan .withFractionalSeconds jika perlu (lihat Lampiran)
        return d
    }()
}
extension JSONEncoder {
    static let immich: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
}
```

**Acceptance:** `GET /server/ping` mengembalikan `{"res":"pong"}` tanpa crash; error 401/500 rapi.

---

## FASE 2 — Data Models (DTO)

**Tujuan:** Struct Swift cocok dengan JSON API untuk fitur inti.

> **Tips akurasi:** unduh `https://<server>/api/spec.json` untuk melihat schema pasti. DTO di bawah cukup untuk mulai; tandai field opsional dengan `?`.

**Tugas:** buat semua DTO di `Models/DTO/`.

**Skeleton (contoh utama — lanjutkan sisanya dengan pola sama):**
```swift
// Models/DTO/AuthDTO.swift
struct LoginRequestDTO: Encodable { let email: String; let password: String }

struct LoginResponseDTO: Decodable {
    let accessToken: String
    let userId: String
    let userEmail: String
    let name: String
    let isAdmin: Bool
    let shouldChangePassword: Bool
}

// Models/DTO/UserDTO.swift
struct UserResponseDTO: Decodable, Identifiable {
    let id: String
    let email: String
    let name: String
    let profileImagePath: String?
    let storageLabel: String?
}

// Models/DTO/ServerDTO.swift
struct ServerPingDTO: Decodable { let res: String }        // "pong"
struct ServerFeaturesDTO: Decodable {
    let smartSearch: Bool
    let facialRecognition: Bool
    let oauth: Bool
    let passwordLogin: Bool
    let search: Bool
}
struct ServerAboutDTO: Decodable { let version: String; let versionUrl: String? }

// Models/DTO/AssetDTO.swift
struct AssetResponseDTO: Decodable, Identifiable {
    let id: String
    let type: String            // "IMAGE" | "VIDEO"
    let originalFileName: String
    let fileCreatedAt: Date
    let isFavorite: Bool
    let isArchived: Bool
    let isTrashed: Bool
    let duration: String?
    let thumbhash: String?
    let localDateTime: Date
    let exifInfo: ExifDTO?
    let people: [PersonDTO]?

    var isVideo: Bool { type == "VIDEO" }
}

struct ExifDTO: Decodable {
    let make: String?; let model: String?
    let exifImageWidth: Int?; let exifImageHeight: Int?
    let fileSizeInByte: Int?
    let dateTimeOriginal: Date?
    let latitude: Double?; let longitude: Double?
    let city: String?; let state: String?; let country: String?
    let lensModel: String?; let fNumber: Double?
    let focalLength: Double?; let iso: Int?; let exposureTime: String?
}

// Models/DTO/TimelineDTO.swift
struct TimeBucketDTO: Decodable { let timeBucket: String; let count: Int }

// Catatan: server baru mengembalikan format columnar (array paralel).
// Buat DTO yang cocok lalu ubah jadi [AssetLite] di repository.
struct TimelineBucketDTO: Decodable {
    let id: [String]
    let ownerId: [String]?
    let isImage: [Bool]?
    let isFavorite: [Bool]?
    let thumbhash: [String?]?
    let fileCreatedAt: [String]?
    let duration: [String?]?
    let ratio: [Double]?
    // Jika server kamu format LAMA (array of object), ganti DTO ini jadi [AssetResponseDTO].
}

// Models/DTO/AlbumDTO.swift
struct AlbumResponseDTO: Decodable, Identifiable {
    let id: String
    let albumName: String
    let description: String?
    let assetCount: Int
    let albumThumbnailAssetId: String?
    let shared: Bool
    let createdAt: Date
    let assets: [AssetResponseDTO]?
}

// Models/DTO/PersonDTO.swift
struct PersonDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let birthDate: Date?
    let thumbnailPath: String?
    let isHidden: Bool
}

// Models/DTO/SearchDTO.swift
struct SearchRequestDTO: Encodable {
    var query: String? = nil          // untuk /search/smart
    var page: Int? = 1
    var type: String? = nil           // "IMAGE"|"VIDEO"
    var isFavorite: Bool? = nil
    var takenAfter: String? = nil
    var takenBefore: String? = nil
    var city: String? = nil
}
struct SearchResponseDTO: Decodable {
    struct AssetsPage: Decodable { let items: [AssetResponseDTO]; let total: Int; let nextPage: String? }
    let assets: AssetsPage
}

// Models/DTO/MemoryDTO.swift
struct MemoryDTO: Decodable, Identifiable {
    let id: String
    let type: String
    let memoryAt: Date
    let assets: [AssetResponseDTO]
}
```

**Domain model ringan untuk grid (dipakai Timeline):**
```swift
// Models/Domain/AssetLite.swift
struct AssetLite: Identifiable, Hashable {
    let id: String
    let isVideo: Bool
    let ratio: Double          // width/height untuk layout
    let thumbhash: String?
    let createdAt: Date
}
```

**Acceptance:** semua DTO compile; 1 unit test decode JSON contoh (dari Swagger) → sukses.

---

## FASE 3 — Onboarding (Server URL + Login)

**Tujuan:** User masukkan server, login, token tersimpan aman, lalu masuk layar utama.

**Endpoint:** `GET /server/ping`, `GET /server/features`, `POST /auth/login`, `POST /auth/validateToken`, `GET /users/me`, `POST /auth/logout`.

### 3A. Keychain & Session (skeleton)
```swift
// Core/Storage/KeychainStore.swift
import Security
import Foundation

enum KeychainStore {
    static func save(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var add = query; add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func delete(_ key: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrAccount as String: key] as CFDictionary)
    }
}
```
```swift
// Core/Auth/SessionManager.swift
import Foundation
import Observation

@MainActor
@Observable
final class SessionManager {
    enum AuthMode: String { case bearer, apiKey }

    private(set) var baseURL: URL?
    private(set) var currentUser: UserResponseDTO?
    var isLoggedIn: Bool = false

    private var token: String?
    private var mode: AuthMode = .bearer

    // header yang otomatis ditempel APIClient
    nonisolated var authHeaders: [String: String] {
        // NOTE: karena @MainActor, baca via snapshot sederhana; untuk simpel,
        // simpan token juga di Keychain dan baca di sini jika perlu.
        MainActor.assumeIsolated {
            guard let token else { return [:] }
            return mode == .bearer ? ["Authorization": "Bearer \(token)"]
                                   : ["x-api-key": token]
        }
    }

    private lazy var api = APIClient(session: self)

    // --- Server URL ---
    func setServer(_ raw: String) throws {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if !s.hasPrefix("http") { s = "https://" + s }
        if s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s + "/api") else { throw APIError.invalidURL }
        baseURL = url
    }
    func ping() async throws { let _: ServerPingDTO = try await api.send(.init(path: "/server/ping")) }
    func features() async throws -> ServerFeaturesDTO { try await api.send(.init(path: "/server/features")) }

    // --- Login ---
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
        try await fetchMe()      // validasi: kalau 401 akan throw
        persist()
        isLoggedIn = true
    }
    private func fetchMe() async throws { currentUser = try await api.send(.init(path: "/users/me")) }

    // --- Restore & Logout ---
    func restore() async {
        guard let server = KeychainStore.read("serverURL"),
              let tok = KeychainStore.read("token"),
              let m = KeychainStore.read("mode").flatMap(AuthMode.init) else { return }
        try? setServer(server.replacingOccurrences(of: "/api", with: ""))
        applyAuth(token: tok, mode: m)
        do { try await validate(); try await fetchMe(); isLoggedIn = true }
        catch { logout() }        // token mati → balik onboarding
    }
    private func validate() async throws { try await api.sendVoid(.init(path: "/auth/validateToken", method: .post)) }

    func logout() {
        Task { try? await api.sendVoid(.init(path: "/auth/logout", method: .post)) }
        token = nil; currentUser = nil; isLoggedIn = false
        ["serverURL","token","mode"].forEach(KeychainStore.delete)
    }

    // --- helpers ---
    private func applyAuth(token: String, mode: AuthMode) { self.token = token; self.mode = mode }
    private func persist() {
        if let baseURL { KeychainStore.save(baseURL.absoluteString, for: "serverURL") }
        if let token { KeychainStore.save(token, for: "token") }
        KeychainStore.save(mode.rawValue, for: "mode")
    }
}
```

### 3B. UI Onboarding (skeleton)
```swift
// Features/Onboarding/OnboardingViewModel.swift
import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    var serverText = ""
    var email = ""; var password = ""; var apiKey = ""
    var features: ServerFeaturesDTO?
    var phase: LoadingPhase<Void> = .idle
    var step: Step = .server
    enum Step { case server, login }

    private let session: SessionManager
    init(session: SessionManager) { self.session = session }

    func connect() async {
        phase = .loading
        do {
            try session.setServer(serverText)
            try await session.ping()
            features = try await session.features()
            step = .login
            phase = .idle
        } catch { phase = .failed((error as? APIError)?.errorDescription ?? String(localized: "Failed to connect")) }
    }
    func loginPassword() async {
        phase = .loading
        do { try await session.loginPassword(email: email, password: password) }
        catch { phase = .failed((error as? APIError)?.errorDescription ?? String(localized: "Sign in failed")) }
    }
    func loginApiKey() async {
        phase = .loading
        do { try await session.loginApiKey(apiKey) }
        catch { phase = .failed(String(localized: "Invalid API Key")) }
    }
}
```
```swift
// Features/Onboarding/OnboardingView.swift
import SwiftUI

struct OnboardingView: View {
    @Environment(SessionManager.self) private var session
    @State private var vm: OnboardingViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm { content(vm) }
                else { ProgressView().onAppear { vm = OnboardingViewModel(session: session) } }
            }
        }
    }

    @ViewBuilder private func content(_ vm: OnboardingViewModel) -> some View {
        @Bindable var vm = vm
        VStack(spacing: 16) {
            if vm.step == .server {
                TextField("https://photos.yourdomain.com", text: $vm.serverText)
                    .textInputAutocapitalization(.never).keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                Button("Connect") { Task { await vm.connect() } }
                    .buttonStyle(.borderedProminent)
            } else {
                TextField("Email", text: $vm.email).textFieldStyle(.roundedBorder)
                SecureField("Password", text: $vm.password).textFieldStyle(.roundedBorder)
                Button("Sign In") { Task { await vm.loginPassword() } }
                    .buttonStyle(.borderedProminent)
                // TODO: tab/pilihan API Key & tombol OAuth (jika vm.features?.oauth == true)
            }
            if case .loading = vm.phase { ProgressView() }
            if case .failed(let msg) = vm.phase { Text(msg).foregroundStyle(.red).font(.footnote) }
        }
        .padding()
        .navigationTitle("Immich")
    }
}
```

**Tugas checklist:**
- [ ] 3.1 KeychainStore + SessionManager.
- [ ] 3.2 Layar Server URL (ping + features).
- [ ] 3.3 Layar Login email/password.
- [ ] 3.4 Login API Key (validasi via `/users/me`).
- [ ] 3.5 Restore session saat app start (`validateToken`).
- [ ] 3.6 Logout.
- [ ] 3.7 (Opsional) OAuth via `ASWebAuthenticationSession` + URL scheme (Fase 3E).

**Acceptance:** login email/password → masuk app; tutup-buka app tetap login; kredensial salah → error rapi; logout → balik onboarding.

---

## FASE 4 — Timeline (Grid Foto Utama)

**Tujuan:** Grid semua foto, dikelompokkan per bulan, scroll cepat, thumbnail lazy + placeholder blur.

**Endpoint:** `GET /timeline/buckets`, `GET /timeline/bucket`, `GET /assets/{id}/thumbnail`.

### 4A. Image loader ber-auth (KUNCI — `AsyncImage` bawaan tidak kirim header → 401)
```swift
// Core/Networking/ImageLoader.swift
import SwiftUI

actor ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    func image(for key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func insert(_ img: UIImage, for key: String) { cache.setObject(img, forKey: key as NSString) }
}

@MainActor
struct AuthImage: View {
    let assetId: String
    var size: String = "thumbnail"      // "thumbnail" | "preview"
    @Environment(SessionManager.self) private var session
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Rectangle().fill(.gray.opacity(0.15)) }   // TODO: ganti dgn thumbhash blur
        }
        .task(id: assetId) { await load() }
    }

    private func load() async {
        let key = "\(assetId)-\(size)"
        if let cached = await ImageCache.shared.image(for: key) { image = cached; return }
        do {
            let api = APIClient(session: session)
            let data = try await api.rawData(.init(
                path: "/assets/\(assetId)/thumbnail",
                query: [.init(name: "size", value: size)]))
            if let ui = UIImage(data: data) {
                await ImageCache.shared.insert(ui, for: key)
                image = ui
            }
        } catch { /* biarkan placeholder */ }
    }
}
```

### 4B. Repository + ViewModel
```swift
// Features/Timeline/TimelineRepository.swift
struct TimelineSection: Identifiable { let id: String; let title: String; var assets: [AssetLite] }

final class TimelineRepository {
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func buckets() async throws -> [TimeBucketDTO] {
        try await api.send(.init(path: "/timeline/buckets",
            query: [.init(name: "isArchived", value: "false")]))
    }
    func bucket(_ timeBucket: String) async throws -> [AssetLite] {
        let dto: TimelineBucketDTO = try await api.send(.init(path: "/timeline/bucket",
            query: [.init(name: "timeBucket", value: timeBucket)]))
        // ubah columnar → [AssetLite]
        return dto.id.enumerated().map { i, id in
            AssetLite(id: id,
                      isVideo: !(dto.isImage?[i] ?? true),
                      ratio: dto.ratio?[i] ?? 1,
                      thumbhash: dto.thumbhash?[i] ?? nil,
                      createdAt: .now)   // TODO: parse dto.fileCreatedAt[i]
        }
    }
}
```
```swift
// Features/Timeline/TimelineViewModel.swift
import Observation

@MainActor
@Observable
final class TimelineViewModel {
    var sections: [TimelineSection] = []
    var phase: LoadingPhase<Void> = .idle
    private var loaded = Set<String>()      // bucket yang sudah di-fetch
    private let repo: TimelineRepository

    init(repo: TimelineRepository) { self.repo = repo }

    func loadBuckets() async {
        phase = .loading
        do {
            let buckets = try await repo.buckets()
            sections = buckets.map { TimelineSection(id: $0.timeBucket,
                                                     title: Self.title($0.timeBucket),
                                                     assets: []) }
            phase = .loaded(())
        } catch { phase = .failed((error as? APIError)?.errorDescription ?? String(localized: "Failed to load")) }
    }

    func loadSectionIfNeeded(_ id: String) async {
        guard !loaded.contains(id) else { return }
        loaded.insert(id)
        if let assets = try? await repo.bucket(id),
           let idx = sections.firstIndex(where: { $0.id == id }) {
            sections[idx].assets = assets
        }
    }

    static func title(_ iso: String) -> String { String(iso.prefix(7)) } // TODO: format jadi "August 2026" (pakai DateFormatter, locale ikut sistem)
}
```

### 4C. View
```swift
// Features/Timeline/TimelineView.swift
import SwiftUI

struct TimelineView: View {
    @Environment(SessionManager.self) private var session
    @State private var vm: TimelineViewModel?
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let vm {
                    LazyVStack(alignment: .leading, pinnedViews: [.sectionHeaders]) {
                        ForEach(vm.sections) { section in
                            Section {
                                LazyVGrid(columns: columns, spacing: 2) {
                                    ForEach(section.assets) { asset in
                                        NavigationLink(value: asset) {
                                            AuthImage(assetId: asset.id)
                                                .aspectRatio(1, contentMode: .fill)
                                                .clipped()
                                        }
                                    }
                                }
                            } header: {
                                Text(section.title).font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6).background(.bar)
                                    .task { await vm.loadSectionIfNeeded(section.id) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Photos")
            .navigationDestination(for: AssetLite.self) { AssetDetailView(asset: $0) } // Fase 5
            .refreshable { await vm?.loadBuckets() }
            .task {
                if vm == nil { vm = TimelineViewModel(repo: .init(api: APIClient(session: session))) }
                await vm?.loadBuckets()
            }
        }
    }
}
```

**Tugas checklist:**
- [ ] 4.1 `AuthImage` + `ImageCache`.
- [ ] 4.2 `TimelineRepository` (buckets + bucket columnar→AssetLite; **parse tanggal beneran**).
- [ ] 4.3 `TimelineViewModel` (lazy load per section).
- [ ] 4.4 `TimelineView` grid + sticky header + pull-to-refresh.
- [ ] 4.5 Placeholder blur via **thumbhash** (decode → UIImage kecil).
- [ ] 4.6 Empty state & error state + retry.
- [ ] 4.7 (Opsional) date scrubber samping.

**Acceptance:** grid tampil urut terbaru→terlama per bulan; scroll ribuan foto mulus; thumbnail muncul dgn placeholder; tap → viewer.

---

## FASE 5 — Asset Detail (Viewer Foto Full)

**Tujuan:** Foto/video layar penuh, swipe antar foto, zoom, info EXIF + peta, aksi (favorite/archive/share/delete).

**Endpoint:** `GET /assets/{id}`, `GET /assets/{id}/thumbnail?size=preview`, `GET /assets/{id}/original`, `PUT /assets/{id}`, `DELETE /assets`, `GET /download/asset/{id}`.

**Skeleton inti:**
```swift
// Features/AssetDetail/AssetDetailViewModel.swift
import Observation

@MainActor @Observable
final class AssetDetailViewModel {
    var detail: AssetResponseDTO?
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func load(_ id: String) async { detail = try? await api.send(.init(path: "/assets/\(id)")) }

    func toggleFavorite(_ id: String, to value: Bool) async {
        struct Body: Encodable { let isFavorite: Bool }
        try? await api.sendVoid(.json("/assets/\(id)", method: .put, body: Body(isFavorite: value)))
    }
    func delete(_ id: String) async {
        struct Body: Encodable { let ids: [String]; let force: Bool }
        try? await api.sendVoid(.json("/assets", method: .delete, body: Body(ids: [id], force: false)))
    }
}
```
```swift
// Features/AssetDetail/AssetDetailView.swift
import SwiftUI

struct AssetDetailView: View {
    let asset: AssetLite
    @Environment(SessionManager.self) private var session
    @State private var vm: AssetDetailViewModel?
    @State private var showInfo = false

    var body: some View {
        AuthImage(assetId: asset.id, size: "preview")   // TODO: upgrade ke original + pinch zoom
            .scaledToFit()
            .ignoresSafeArea()
            .overlay(alignment: .bottom) { toolbar }
            .sheet(isPresented: $showInfo) { InfoPanel(detail: vm?.detail) }
            .task {
                if vm == nil { vm = AssetDetailViewModel(api: APIClient(session: session)) }
                await vm?.load(asset.id)
            }
    }

    private var toolbar: some View {
        HStack(spacing: 32) {
            Button { /* share via /download/asset/{id} */ } label: { Image(systemName: "square.and.arrow.up") }
            Button { Task { await vm?.toggleFavorite(asset.id, to: true) } } label: { Image(systemName: "heart") }
            Button { showInfo = true } label: { Image(systemName: "info.circle") }
            Button(role: .destructive) { Task { await vm?.delete(asset.id) } } label: { Image(systemName: "trash") }
        }
        .padding().background(.bar)
    }
}

struct InfoPanel: View {
    let detail: AssetResponseDTO?
    var body: some View {
        List {
            if let d = detail {
                Section("File") { Text(d.originalFileName); Text(d.fileCreatedAt.formatted()) }
                if let e = d.exifInfo {
                    Section("Camera") {
                        if let m = e.make, let mo = e.model { Text("\(m) \(mo)") }
                        if let f = e.fNumber { Text("f/\(f, specifier: "%.1f")") }
                        if let iso = e.iso { Text("ISO \(iso)") }
                    }
                    // TODO: Map(MapKit) jika e.latitude/longitude ada
                }
            } else { ProgressView() }
        }
    }
}
```

**Tugas checklist:**
- [ ] 5.1 Swipe antar asset (`TabView(.page)` dgn daftar dari Timeline).
- [ ] 5.2 Load bertingkat: preview → original.
- [ ] 5.3 Pinch-zoom & double-tap (bungkus `UIScrollView` via `UIViewRepresentable` untuk halus).
- [ ] 5.4 Video via `AVPlayer` + `AVURLAsset` header auth.
- [ ] 5.5 Toolbar: share, favorite, archive, delete.
- [ ] 5.6 Panel info EXIF + peta MapKit.
- [ ] 5.7 Chip wajah → People (Fase 8).
- [ ] 5.8 Share/Save original ke Photos.
- [ ] 5.9 Swipe-down untuk tutup.
- [ ] 5.10 Sinkron perubahan balik ke grid.

**Acceptance:** tap foto → full screen; swipe pindah; zoom mulus; video jalan; favorite/delete tercermin di grid; info + peta tampil.

---

## FASE 6 — Albums

**Tujuan:** Lihat daftar album, buka isi, buat album, tambah/hapus foto.

**Endpoint:** `GET /albums`, `GET /albums/{id}`, `POST /albums`, `PUT /albums/{id}/assets`, `DELETE /albums/{id}/assets`, `DELETE /albums/{id}`.

**Skeleton repository:**
```swift
final class AlbumRepository {
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func all() async throws -> [AlbumResponseDTO] { try await api.send(.init(path: "/albums")) }
    func detail(_ id: String) async throws -> AlbumResponseDTO { try await api.send(.init(path: "/albums/\(id)")) }

    func create(name: String, assetIds: [String]) async throws -> AlbumResponseDTO {
        struct Body: Encodable { let albumName: String; let assetIds: [String] }
        return try await api.send(.json("/albums", method: .post, body: Body(albumName: name, assetIds: assetIds)))
    }
    func addAssets(_ ids: [String], to albumId: String) async throws {
        struct Body: Encodable { let ids: [String] }
        try await api.sendVoid(.json("/albums/\(albumId)/assets", method: .put, body: Body(ids: ids)))
    }
    func removeAssets(_ ids: [String], from albumId: String) async throws {
        struct Body: Encodable { let ids: [String] }
        try await api.sendVoid(.json("/albums/\(albumId)/assets", method: .delete, body: Body(ids: ids)))
    }
}
```

**Tugas checklist:**
- [ ] 6.1 `AlbumsListView` (grid album; pisah "Saya" vs "Dibagikan" via `shared`).
- [ ] 6.2 `AlbumDetailView` (reuse grid Fase 4, sumber `detail(id).assets`).
- [ ] 6.3 Buat album (`POST /albums`).
- [ ] 6.4 Tambah/hapus asset (butuh multi-select di grid).
- [ ] 6.5 Rename/hapus album.

**Acceptance:** lihat, buka, buat album; tambah/hapus foto berfungsi.

---

## FASE 7 — Search & Explore

**Tujuan:** Cari teks bebas (smart), metadata (tanggal/lokasi/tipe), Explore.

**Endpoint:** `POST /search/smart`, `POST /search/metadata`, `GET /search/explore`, `GET /search/suggestions`.

**Skeleton:**
```swift
final class SearchRepository {
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func smart(_ query: String, page: Int = 1) async throws -> [AssetResponseDTO] {
        let res: SearchResponseDTO = try await api.send(
            .json("/search/smart", method: .post, body: SearchRequestDTO(query: query, page: page)))
        return res.assets.items
    }
    func metadata(_ req: SearchRequestDTO) async throws -> [AssetResponseDTO] {
        let res: SearchResponseDTO = try await api.send(.json("/search/metadata", method: .post, body: req))
        return res.assets.items
    }
}
```

**Tugas checklist:**
- [ ] 7.1 `SearchView` + `.searchable`. Default smart (jika `features.smartSearch`), fallback metadata.
- [ ] 7.2 Hasil grid + paginasi (`nextPage`).
- [ ] 7.3 Explore page (`/search/explore`) — kota & things.
- [ ] 7.4 Filter metadata (tanggal, tipe, favorit, kota).
- [ ] 7.5 Autocomplete via `/search/suggestions`.

**Acceptance:** ketik kata → foto relevan (jika smart aktif); filter tanggal/lokasi jalan.

---

## FASE 8 — People / Faces

**Tujuan:** Daftar orang, foto per orang, beri nama, sembunyikan.

**Endpoint:** `GET /people`, `GET /people/{id}`, `GET /people/{id}/thumbnail`, `PUT /people/{id}`.

**Skeleton:**
```swift
final class PeopleRepository {
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func all() async throws -> [PersonDTO] {
        struct Wrap: Decodable { let people: [PersonDTO] }
        return try await (api.send(.init(path: "/people")) as Wrap).people
    }
    func rename(_ id: String, name: String) async throws {
        struct Body: Encodable { let name: String }
        try await api.sendVoid(.json("/people/\(id)", method: .put, body: Body(name: name)))
    }
}
```

**Tugas checklist:**
- [ ] 8.1 `PeopleView` grid lingkaran wajah + nama.
- [ ] 8.2 `PersonDetailView` (foto orang; edit nama).
- [ ] 8.3 Sembunyikan orang (`isHidden`).
- [ ] 8.4 Integrasi chip wajah dari viewer (Fase 5.7).

**Acceptance:** daftar orang tampil; buka foto per orang; beri/ubah nama.

---

## FASE 9 — Memories

**Tujuan:** "Hari ini X tahun lalu" ala stories.

**Endpoint:** `GET /memories`.

**Tugas checklist:**
- [ ] 9.1 `MemoriesView` — baris kartu di atas timeline / tab sendiri.
- [ ] 9.2 Story viewer full screen auto-advance (tap kiri/kanan, tahan = pause).
- [ ] 9.3 Tap asset → viewer normal (Fase 5).

**Acceptance:** memories muncul (jika ada); story viewer mulus.

---

## FASE 10 — Backup / Upload Foto dari HP

**Tujuan:** Upload foto/video dari galeri ke server, dengan deteksi duplikat. **Fase paling kompleks — kerjakan bertahap: upload manual dulu, baru auto-backup.**

**Endpoint:** `POST /assets` (multipart), `POST /assets/bulk-upload-check`, `GET /server/storage`.

**Skeleton upload multipart:**
```swift
// Core/Networking/APIClient+Upload.swift
extension APIClient {
    func uploadAsset(fileURL: URL, deviceAssetId: String, deviceId: String,
                     createdAt: Date, modifiedAt: Date) async throws -> String {
        guard let baseURL = sessionBaseURL else { throw APIError.invalidURL }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: baseURL.appendingPathComponent("/assets"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        for (k, v) in sessionAuthHeaders { req.setValue(v, forHTTPHeaderField: k) }

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("deviceAssetId", deviceAssetId)
        field("deviceId", deviceId)
        field("fileCreatedAt", ISO8601DateFormatter().string(from: createdAt))
        field("fileModifiedAt", ISO8601DateFormatter().string(from: modifiedAt))
        field("isFavorite", "false")

        let fileData = try Data(contentsOf: fileURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"assetData\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData); body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, resp) = try await URLSession.shared.upload(for: req, from: body)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: (resp as? HTTPURLResponse)?.statusCode ?? -1, message: nil)
        }
        struct R: Decodable { let id: String }
        return try JSONDecoder.immich.decode(R.self, from: data).id
    }
    // NOTE: tambahkan properti sessionBaseURL/sessionAuthHeaders yang mengekspos dari SessionManager.
}
```

**Tugas checklist:**
- [ ] 10.1 Izin `PHPhotoLibrary` + `NSPhotoLibraryUsageDescription` di Info.plist.
- [ ] 10.2 Pilih manual via `PhotosPicker`.
- [ ] 10.3 Export `PHAsset` → file temp → `uploadAsset`.
- [ ] 10.4 Cek duplikat via `bulk-upload-check` (skip yang sudah ada).
- [ ] 10.5 Auto-backup: enumerasi `PHAsset`, antre yang belum, upload berurutan, `URLSession` background config.
- [ ] 10.6 UI progress (X dari Y, jeda/lanjut, "hanya Wi-Fi").
- [ ] 10.7 Retry gagal, lanjut item berikutnya, ringkasan.

**Acceptance (minimal):** pilih foto → terunggah → muncul di timeline server; duplikat tidak dobel. (Lanjutan) auto-backup seluruh galeri dgn progress & bisa dijeda.

---

## FASE 11 — Settings & Profil

**Tujuan:** Pusat pengaturan & info akun.

**Endpoint:** `GET /users/me`, `GET /users/me/preferences`, `GET /server/about`, `GET /server/storage`, `POST /auth/logout`.

**Tugas checklist:**
- [ ] 11.1 Profil (foto, nama, email, admin, storage label).
- [ ] 11.2 Penyimpanan (`/server/storage`).
- [ ] 11.3 Backup settings (integrasi Fase 10).
- [ ] 11.4 Tampilan (tema, jumlah kolom grid).
- [ ] 11.5 Info server & versi app.
- [ ] 11.6 Logout & ganti server.
- [ ] 11.7 Bersihkan cache thumbnail.

**Acceptance:** setelan tersimpan (UserDefaults untuk preferensi, Keychain untuk auth) & berpengaruh.

---

## FASE 12 — Sinkronisasi & Cache Lokal (SwiftData)

**Tujuan:** App cepat & bisa dibuka offline; delta sync hemat kuota.

**Endpoint:** `POST /sync/full-sync`, `POST /sync/delta-sync`.

**Skeleton model:**
```swift
import SwiftData

@Model final class CachedAsset {
    @Attribute(.unique) var id: String
    var isVideo: Bool
    var createdAt: Date
    var thumbhash: String?
    var isFavorite: Bool
    init(id: String, isVideo: Bool, createdAt: Date, thumbhash: String?, isFavorite: Bool) {
        self.id = id; self.isVideo = isVideo; self.createdAt = createdAt
        self.thumbhash = thumbhash; self.isFavorite = isFavorite
    }
}
@Model final class BackupRecord {
    @Attribute(.unique) var deviceAssetId: String
    var uploadedAssetId: String?
    var uploadedAt: Date?
    init(deviceAssetId: String) { self.deviceAssetId = deviceAssetId }
}
```

**Tugas checklist:**
- [ ] 12.1 Set up `ModelContainer` di `ImmichApp`.
- [ ] 12.2 Full sync pertama → simpan ke SwiftData.
- [ ] 12.3 Delta sync (`updatedAfter`/ackToken) → merge (tambah/ubah/hapus).
- [ ] 12.4 UI baca cache dulu, refresh di background (stale-while-revalidate).
- [ ] 12.5 Cache thumbnail disk (folder Caches, batas ukuran, LRU).
- [ ] 12.6 Offline mode + banner "Offline".

**Acceptance:** buka tanpa internet → foto terakhir tampil; sync berikut hanya tarik perubahan.

---

## FASE 13 — Polish, Aksesibilitas & Rilis

**Tugas checklist:**
- [ ] 13.1 Desain iOS 26 (Liquid Glass, `.toolbar`, Dark Mode penuh).
- [ ] 13.2 Aksesibilitas (VoiceOver label, Dynamic Type).
- [ ] 13.3 Haptics untuk aksi penting.
- [ ] 13.4 Error/empty states konsisten.
- [ ] 13.5 Performance (Instruments: scroll 10.000+ foto, cek memory leak cache).
- [ ] 13.6 App Icon & Launch Screen.
- [ ] 13.7 Localization: buat String Catalog (`Localizable.xcstrings`), base = **English** (sudah default sejak awal), lalu tambahkan terjemahan **Bahasa Indonesia (id)**. Karena semua string sudah dibungkus `String(localized:)`/`LocalizedStringKey`, cukup isi terjemahannya tanpa ubah kode.
- [ ] 13.8 Privasi (App Privacy, ATS — idealnya paksa HTTPS).
- [ ] 13.9 TestFlight build + catatan rilis.

**Acceptance:** stabil, cepat, aksesibel, siap distribusi.

---

## Strategi Testing (lakukan di setiap fase)

- **Unit test:** `APIClient` (mock `URLProtocol`), decoding DTO (JSON dari Swagger), mapper columnar→AssetLite, logika duplikat backup.
- **UI test:** onboarding→login→timeline, buka viewer, upload 1 foto.
- **Manual checklist** = "Acceptance" tiap fase.
- **Uji dengan server asli** sedini mungkin (jangan hanya mock).

---

## Urutan Pengerjaan (MVP dulu)

1. **MVP end-to-end:** Fase 0 → 1 → 2 → 3 (login email/pass) → 4 (timeline) → 5 (viewer). Setelah ini: "login + lihat semua foto + buka foto" tercapai.
2. **Navigasi:** 6 (Albums) → 7 (Search) → 8 (People) → 9 (Memories).
3. **Backup:** 10 (mulai upload manual).
4. **Kualitas:** 11 → 12 (cache/offline) → 13 (polish/rilis).

---

## Lampiran A — Verifikasi bentuk API

Struktur beberapa response (timeline & sync) berbeda antar versi server. Selalu cek sumber kebenaran:
1. `https://<server>/api/docs` (Swagger UI) untuk coba langsung.
2. `https://<server>/api/spec.json` (OpenAPI) untuk schema pasti.
3. Referensi resmi: <https://api.immich.app/endpoints>.
4. Jika DTO gagal decode → baca error `.decoding`, sesuaikan field/optional.

## Lampiran B — Jebakan yang sering bikin bug

- **Thumbnail 401:** `AsyncImage` bawaan tidak kirim header auth → wajib `AuthImage` (Fase 4A).
- **Video butuh header:** `AVURLAsset(url:options:)` dgn `"AVURLAssetHTTPHeaderFieldsKey": headers`.
- **Upload multipart:** JANGAN set `Content-Type: application/json`; biarkan boundary multipart.
- **Tanggal ISO dgn milidetik:** kalau decode Date gagal, pakai custom `DateFormatter` dengan `yyyy-MM-dd'T'HH:mm:ss.SSSZ` atau `ISO8601DateFormatter` dgn `.withFractionalSeconds`.
- **Timeline columnar vs object:** cek versi server; sesuaikan `TimelineBucketDTO`.
- **Swift 6 concurrency:** ViewModel & View `@MainActor`; hati-hati akses `@Observable` lintas actor.

## Lampiran C — Definition of Done per fitur

Fitur selesai jika: (a) semua checklist ✅, (b) acceptance terpenuhi dengan server asli, (c) minimal 1 test otomatis, (d) tidak ada warning concurrency Swift 6, (e) sudah di-commit dgn pesan jelas.
