import Foundation

class APIClient {
    let session: SessionManager
    private let urlSession: URLSession

    init(session: SessionManager, urlSession: URLSession = .shared) {
        self.session = session
        self.urlSession = urlSession
    }

    /// Session khusus byte gambar.
    ///
    /// `URLCache` DIMATIKAN di sini. Kita sudah menyimpan byte-nya sendiri di
    /// disk; membiarkan URLSession menyimpannya lagi berarti setiap thumbnail
    /// ditulis dua kali dan mengaduk cache bersama milik seluruh proses.
    ///
    /// Batas koneksi per host dinaikkan karena thumbnail itu kecil dan banyak —
    /// enam koneksi bawaan membuat antreannya jauh lebih panjang dari perlunya.
    static let imageSessionConfiguration: URLSessionConfiguration = {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        return config
    }()

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

    func rawData(_ endpoint: Endpoint) async throws -> Data {
        let (data, http) = try await perform(endpoint)
        try validate(http, data)
        return data
    }

    /// Respons JSON Lines (mis. /sync/stream): satu objek JSON per baris.
    func streamLines(_ endpoint: Endpoint) async throws -> AsyncLineSequence<URLSession.AsyncBytes> {
        let req = try await makeRequest(endpoint)
        let result: (URLSession.AsyncBytes, URLResponse)
        do {
            result = try await urlSession.bytes(for: req)
        } catch let e as URLError where Self.meansOffline(e.code) {
            throw APIError.notConnected
        }
        let (bytes, resp) = result
        guard let http = resp as? HTTPURLResponse else { throw APIError.unknown }
        switch http.statusCode {
        case 200..<300: return bytes.lines
        case 401:       throw APIError.unauthorized
        default:        throw APIError.server(status: http.statusCode, message: nil)
        }
    }

    /// "Tidak sampai ke server" — LEBIH LUAS dari sekadar tidak ada internet.
    ///
    /// Sebelumnya hanya `.notConnectedToInternet` yang dikenali, dan itu kasus
    /// yang justru paling jarang: server Immich biasanya di jaringan sendiri.
    /// Keluar dari jangkauan Wi‑Fi rumah menghasilkan `.cannotConnectToHost`
    /// atau `.timedOut`, dan keduanya dulu lolos sebagai `URLError` mentah —
    /// lapisan di atasnya tidak bisa membedakan "sedang di luar" dari "ada yang
    /// rusak", dan menampilkan pesan gagal yang membingungkan untuk keadaan yang
    /// sepenuhnya wajar.
    private static func meansOffline(_ code: URLError.Code) -> Bool {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .timedOut, .dataNotAllowed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }

    private func perform(_ endpoint: Endpoint) async throws -> (Data, HTTPURLResponse) {
        let req = try await makeRequest(endpoint)
        do {
            let (data, resp) = try await urlSession.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw APIError.unknown }
            return (data, http)
        } catch let e as URLError where Self.meansOffline(e.code) {
            throw APIError.notConnected
        }
    }

    private func makeRequest(_ endpoint: Endpoint) async throws -> URLRequest {
        // Konteksnya dibaca dari cuplikan yang tidak terikat main actor.
        //
        // `session.requestContext` adalah properti @MainActor: membacanya berarti
        // setiap permintaan — termasuk ratusan thumbnail saat menggulir —
        // menunggu giliran di main thread, bersaing dengan penggambaran.
        let (baseURL, authHeaders) = await session.snapshot
        guard let baseURL else { throw APIError.invalidURL }
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
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in authHeaders { req.setValue(v, forHTTPHeaderField: k) }
        for (k, v) in endpoint.extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        return req
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
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = ISO8601DateFormatter.immichFractional.date(from: raw)
                ?? ISO8601DateFormatter.immichPlain.date(from: raw)
                ?? DateFormatter.immichDateOnly.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid ISO8601 date: \(raw)")
        }
        return d
    }()
}

extension ISO8601DateFormatter {
    // Immich mengirim tanggal dengan pecahan detik ("2024-01-01T12:00:00.000Z"),
    // beberapa field tanpa pecahan, dan birthDate berformat tanggal saja.
    static let immichFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let immichPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

extension DateFormatter {
    static let immichDateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

extension JSONEncoder {
    static let immich: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
