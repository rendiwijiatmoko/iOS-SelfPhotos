import Foundation

final class BackupRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func checkDuplicates(assetIds: [String]) async throws -> [String] {
        struct Body: Encodable {
            let assetIds: [String]
        }
        struct Response: Decodable {
            let duplicates: [String]
        }
        let response: Response = try await api.send(.json("/assets/bulk-upload-check", method: .post, body: Body(assetIds: assetIds)))
        return response.duplicates
    }

    func uploadAsset(
        fileURL: URL,
        deviceAssetId: String,
        deviceId: String,
        createdAt: Date,
        modifiedAt: Date
    ) async throws -> String {
        guard let baseURL = api.session.baseURL else { throw APIError.invalidURL }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("/assets"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        for (k, v) in api.session.authHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }

        var body = Data()

        func addField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        addField("deviceAssetId", deviceAssetId)
        addField("deviceId", deviceId)
        addField("fileCreatedAt", ISO8601DateFormatter().string(from: createdAt))
        addField("fileModifiedAt", ISO8601DateFormatter().string(from: modifiedAt))
        addField("isFavorite", "false")

        let fileData = try Data(contentsOf: fileURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"assetData\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
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
        }

        let result = try JSONDecoder.immich.decode(UploadResponse.self, from: data)
        return result.id
    }

    func getStorageInfo() async throws -> ServerStorageDTO {
        try await api.send(.init(path: "/server/storage"))
    }
}
