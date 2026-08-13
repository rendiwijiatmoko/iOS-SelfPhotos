import CryptoKit
import Foundation

struct SharedUploadCredential: Equatable, Sendable {
    let apiURL: URL
    let owner: SharedUploadOwner
    let authHeaders: [String: String]
}

enum SharedUploadClientError: LocalizedError {
    case invalidResponse
    case server(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: "The Immich server returned an invalid response.")
        case .server(let status, let message):
            if let message, !message.isEmpty {
                String(localized: "Immich returned HTTP \(status): \(message)")
            } else {
                String(localized: "Immich returned HTTP \(status).")
            }
        }
    }
}

struct SharedUploadClient: Sendable {
    private let credential: SharedUploadCredential

    init(credential: SharedUploadCredential) {
        self.credential = credential
    }

    @discardableResult
    func upload(
        item: SharedUploadItem,
        fileURL: URL,
        bodyDirectory: URL
    ) async throws -> String {
        let checksum = try await checksum(for: fileURL)
        let bodyURL = try await makeMultipartBody(
            item: item,
            sourceURL: fileURL,
            checksum: checksum,
            directory: bodyDirectory)
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        let boundary = bodyURL.deletingPathExtension().lastPathComponent
        var request = URLRequest(url: credential.apiURL.appendingPathComponent("assets"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type")
        request.setValue(checksum, forHTTPHeaderField: "x-immich-checksum")
        credential.authHeaders.forEach {
            request.setValue($1, forHTTPHeaderField: $0)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.upload(for: request, fromFile: bodyURL)

        guard let http = response as? HTTPURLResponse else {
            throw SharedUploadClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SharedUploadClientError.server(
                status: http.statusCode,
                message: String(data: data, encoding: .utf8))
        }

        struct Response: Decodable { let id: String }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw SharedUploadClientError.invalidResponse
        }
        return decoded.id
    }

    private func checksum(for url: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let input = try FileHandle(forReadingFrom: url)
            defer { try? input.close() }
            var hasher = Insecure.SHA1()
            while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                try Task.checkCancellation()
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }

    /// Nama body adalah boundary-nya juga. Itu menghindari metadata kedua yang
    /// dapat hilang bila extension dihentikan di tengah persiapan.
    private func makeMultipartBody(
        item: SharedUploadItem,
        sourceURL: URL,
        checksum: String,
        directory: URL
    ) async throws -> URL {
        try await Task.detached(priority: .utility) {
            let boundary = "Boundary-\(UUID().uuidString)"
            let outputURL = directory.appendingPathComponent(boundary)
                .appendingPathExtension("multipart")
            guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
                throw SharedUploadClientError.invalidResponse
            }

            do {
                let output = try FileHandle(forWritingTo: outputURL)
                defer { try? output.close() }

                func write(_ string: String) throws {
                    try output.write(contentsOf: Data(string.utf8))
                }

                let iso = ISO8601DateFormatter()
                let fields: [(String, String)] = [
                    ("deviceAssetId", "share-\(item.id.uuidString)"),
                    ("deviceId", SharedDeviceIdentity.current),
                    ("fileCreatedAt", iso.string(from: item.createdAt)),
                    ("fileModifiedAt", iso.string(from: item.modifiedAt)),
                    ("filename", item.filename),
                ]
                for (name, value) in fields {
                    try write("--\(boundary)\r\n")
                    try write("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
                    try write("\(value)\r\n")
                }

                let safeFilename = item.filename.replacingOccurrences(of: "\"", with: "'")
                try write("--\(boundary)\r\n")
                try write("Content-Disposition: form-data; name=\"assetData\"; filename=\"\(safeFilename)\"\r\n")
                try write("Content-Type: \(item.contentType)\r\n\r\n")

                let input = try FileHandle(forReadingFrom: sourceURL)
                defer { try? input.close() }
                while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                    try Task.checkCancellation()
                    try output.write(contentsOf: chunk)
                }
                try write("\r\n--\(boundary)--\r\n")
                return outputURL
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                throw error
            }
        }.value
    }
}
