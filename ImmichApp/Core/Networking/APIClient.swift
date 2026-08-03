import Foundation

final class APIClient {
    private(set) var session: SessionManager
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
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let immich: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
