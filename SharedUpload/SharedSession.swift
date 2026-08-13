import Foundation
import Security

enum SelfPhotosSharedContainer {
    static let appGroup = "group.xyz.0xmwehehe.ImmichApp"
    static let keychainAccessGroup = "5KQGTJX2K7.xyz.0xmwehehe.ImmichApp.shared"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static var rootURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup)
    }
}

/// Keychain yang dapat dibaca aplikasi utama dan Share Extension.
///
/// Entri lama SelfPhotos tidak memakai access group. `read` memigrasikannya
/// saat aplikasi utama pertama kali dibuka setelah pembaruan; extension tidak
/// pernah menerima salinan token di UserDefaults atau berkas App Group.
enum SharedKeychainStore {
    static func save(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query = baseQuery(key, shared: true)
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        // Hosted unit tests do not carry the app's keychain entitlement. Keep
        // the legacy fallback there without weakening the shipping app path.
        if SecItemAdd(add as CFDictionary, nil) != errSecSuccess {
            saveLegacy(data, for: key)
        }
    }

    static func read(_ key: String) -> String? {
        if let shared = read(key, shared: true) { return shared }
        guard let legacy = read(key, shared: false) else { return nil }
        save(legacy, for: key)
        return legacy
    }

    static func delete(_ key: String) {
        SecItemDelete(baseQuery(key, shared: true) as CFDictionary)
        SecItemDelete(baseQuery(key, shared: false) as CFDictionary)
    }

    private static func baseQuery(_ key: String, shared: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        if shared {
            query[kSecAttrAccessGroup as String] = SelfPhotosSharedContainer.keychainAccessGroup
        }
        return query
    }

    private static func read(_ key: String, shared: Bool) -> String? {
        var query = baseQuery(key, shared: shared)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveLegacy(_ data: Data, for key: String) {
        let query = baseQuery(key, shared: false)
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
}

struct SharedImmichSession: Codable, Equatable, Sendable {
    let apiURL: URL
    let userID: String
    let authMode: String

    var displayServerURL: String {
        var value = apiURL.absoluteString
        if value.hasSuffix("/api") { value.removeLast(4) }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    var owner: SharedUploadOwner {
        SharedUploadOwner(server: apiURL.absoluteString, userID: userID)
    }

    func credential() -> SharedUploadCredential? {
        guard let token = SharedKeychainStore.read("token"), !token.isEmpty else {
            return nil
        }
        let headers = authMode == "apiKey"
            ? ["x-api-key": token]
            : ["Authorization": "Bearer \(token)"]
        return SharedUploadCredential(
            apiURL: apiURL,
            owner: owner,
            authHeaders: headers)
    }
}

enum SharedSessionStore {
    private static let key = "share.session.v1"

    static func save(apiURL: URL, userID: String, authMode: String) {
        let snapshot = SharedImmichSession(
            apiURL: apiURL,
            userID: userID,
            authMode: authMode)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        SelfPhotosSharedContainer.defaults.set(data, forKey: key)
    }

    static func load() -> SharedImmichSession? {
        guard let data = SelfPhotosSharedContainer.defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(SharedImmichSession.self, from: data)
    }

    static func credential() -> SharedUploadCredential? {
        load()?.credential()
    }

    static func clear() {
        SelfPhotosSharedContainer.defaults.removeObject(forKey: key)
    }
}

enum SharedDeviceIdentity {
    private static let key = "device.identity"

    static let current: String = {
        let defaults = SelfPhotosSharedContainer.defaults
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }

        // Migrate the value written by versions before Share Extension support.
        if let legacy = UserDefaults.standard.string(forKey: key), !legacy.isEmpty {
            defaults.set(legacy, forKey: key)
            return legacy
        }

        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: key)
        return fresh
    }()
}
