import CryptoKit
import Foundation

class BackupRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// SHA1 hex dari isi file — dipakai server untuk deteksi duplikat.
    /// Nonisolated async supaya hashing file besar tidak terjadi di main thread.
    func checksum(for data: Data) async -> String {
        Insecure.SHA1.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// POST /assets/bulk-upload-check menerima {assets: [{id, checksum}]} dan
    /// menjawab {results: [{id, action, reason, ...}]}. Mengembalikan id yang
    /// ditolak karena duplikat.
    func checkDuplicates(_ candidates: [(id: String, checksum: String)]) async throws -> Set<String> {
        struct AssetCheck: Encodable { let id: String; let checksum: String }
        struct Body: Encodable { let assets: [AssetCheck] }
        struct ResultEntry: Decodable {
            let id: String
            let action: String
            let reason: String?
        }
        struct Response: Decodable { let results: [ResultEntry] }

        let body = Body(assets: candidates.map { AssetCheck(id: $0.id, checksum: $0.checksum) })
        let response: Response = try await api.send(.json("/assets/bulk-upload-check", method: .post, body: body))
        return Set(response.results
            .filter { $0.action == "reject" && $0.reason == "duplicate" }
            .map(\.id))
    }

    /// POST /assets (multipart). Field mengikuti AssetMediaCreateDto:
    /// assetData + fileCreatedAt + fileModifiedAt wajib; deviceAssetId/deviceId
    /// sudah tidak ada di API dan akan ditolak validasi server.
    func uploadAsset(
        data fileData: Data,
        filename: String,
        checksum: String,
        createdAt: Date,
        modifiedAt: Date
    ) async throws -> String {
        let (baseURL, authHeaders) = await api.session.requestContext
        guard let baseURL else { throw APIError.invalidURL }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("/assets"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(checksum, forHTTPHeaderField: "x-immich-checksum")

        for (k, v) in authHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }

        var body = Data()

        func addField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        addField("fileCreatedAt", ISO8601DateFormatter().string(from: createdAt))
        addField("fileModifiedAt", ISO8601DateFormatter().string(from: modifiedAt))
        addField("filename", filename)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"assetData\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.server(status: (response as? HTTPURLResponse)?.statusCode ?? -1, message: nil)
        }

        struct UploadResponse: Decodable {
            let id: String
            let status: String?
        }

        let result = try JSONDecoder.immich.decode(UploadResponse.self, from: data)
        return result.id
    }

    func getStorageInfo() async throws -> ServerStorageDTO {
        try await api.send(.init(path: "/server/storage"))
    }
}
