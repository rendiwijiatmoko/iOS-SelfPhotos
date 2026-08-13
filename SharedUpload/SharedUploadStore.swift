import Foundation

struct SharedUploadOwner: Codable, Equatable, Sendable {
    let server: String
    let userID: String
}

enum SharedUploadItemState: String, Codable, Sendable {
    case queued
    case uploading
    case uploaded
}

struct SharedUploadItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let filename: String
    let relativePath: String
    let contentType: String
    let byteCount: Int64
    let createdAt: Date
    let modifiedAt: Date
    var state: SharedUploadItemState
    var lastError: String?
}

struct SharedUploadBatch: Codable, Equatable, Identifiable, Sendable {
    var version = 1
    let id: UUID
    let owner: SharedUploadOwner
    let createdAt: Date
    var items: [SharedUploadItem]
}

enum SharedUploadStoreError: LocalizedError {
    case appGroupUnavailable
    case invalidFilename

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            String(localized: "SelfPhotos could not access its shared upload storage.")
        case .invalidFilename:
            String(localized: "One of the shared files has an invalid name.")
        }
    }
}

/// Ledger per batch, bukan satu JSON global. Dengan begitu proses extension dan
/// aplikasi utama tidak menimpa batch satu sama lain saat keduanya aktif.
actor SharedUploadStore {
    static let shared = SharedUploadStore()

    private let rootURL: URL?
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.rootURL = rootURL ?? SelfPhotosSharedContainer.rootURL?
            .appendingPathComponent("ShareUploadInbox", isDirectory: true)
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func makeBatchDirectory(id: UUID) throws -> URL {
        guard let rootURL else { throw SharedUploadStoreError.appGroupUnavailable }
        let directory = rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        return directory
    }

    func save(_ batch: SharedUploadBatch) throws {
        let directory = try makeBatchDirectory(id: batch.id)
        let target = directory.appendingPathComponent("manifest.json")
        let temporary = directory.appendingPathComponent("manifest-\(UUID().uuidString).tmp")
        let data = try encoder.encode(batch)
        try data.write(to: temporary, options: .atomic)
        if fileManager.fileExists(atPath: target.path) {
            _ = try fileManager.replaceItemAt(target, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: target)
        }
    }

    func batches(for owner: SharedUploadOwner) throws -> [SharedUploadBatch] {
        guard let rootURL else { throw SharedUploadStoreError.appGroupUnavailable }
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        let directories = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])

        return directories.compactMap { directory in
            let manifest = directory.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifest),
                  let batch = try? decoder.decode(SharedUploadBatch.self, from: data),
                  batch.version == 1,
                  batch.owner == owner
            else { return nil }
            return batch
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    func fileURL(for item: SharedUploadItem, batchID: UUID) throws -> URL {
        let directory = try makeBatchDirectory(id: batchID)
        let candidate = directory.appendingPathComponent(item.relativePath)
            .standardizedFileURL
        guard candidate.deletingLastPathComponent() == directory.standardizedFileURL else {
            throw SharedUploadStoreError.invalidFilename
        }
        return candidate
    }

    func removeFile(for item: SharedUploadItem, batchID: UUID) throws {
        let url = try fileURL(for: item, batchID: batchID)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func removeBatch(id: UUID) throws {
        guard let rootURL else { throw SharedUploadStoreError.appGroupUnavailable }
        let directory = rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }
}
