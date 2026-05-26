import CryptoKit
import Foundation
import Security

enum SecureHistoryCodec {
    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.romantools.aivoice"
    }
    private static let account = "transcription-history-key"
    private static let keySize = 32

    static func encrypt(_ data: Data) throws -> Data {
        let key = SymmetricKey(data: try encryptionKeyData())
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw CocoaError(.fileWriteUnknown)
        }
        return combined
    }

    static func decrypt(_ data: Data) throws -> Data {
        let key = SymmetricKey(data: try encryptionKeyData())
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    private static func encryptionKeyData() throws -> Data {
        if let existingKey = try? readKey() {
            return existingKey
        }

        if let existingKey = try? readLocalKey() {
            return existingKey
        }

        var bytes = [UInt8](repeating: 0, count: keySize)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        let data = Data(bytes)
        do {
            try saveKey(data)
        } catch {
            try saveLocalKey(data)
        }
        return data
    }

    private static func readKey() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return item as? Data
    }

    private static func saveKey(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private static var localKeyURL: URL {
        AIVoiceStorage.appDirectory.appendingPathComponent(".history.key")
    }

    private static func readLocalKey() throws -> Data? {
        guard FileManager.default.fileExists(atPath: localKeyURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: localKeyURL)
        return data.count == keySize ? data : nil
    }

    private static func saveLocalKey(_ data: Data) throws {
        try AIVoiceStorage.writeProtected(data, to: localKeyURL)
    }
}
