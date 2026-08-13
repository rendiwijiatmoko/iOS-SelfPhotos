import Foundation

enum KeychainStore {
    static func save(_ value: String, for key: String) {
        SharedKeychainStore.save(value, for: key)
    }

    static func read(_ key: String) -> String? {
        SharedKeychainStore.read(key)
    }

    static func delete(_ key: String) {
        SharedKeychainStore.delete(key)
    }
}
