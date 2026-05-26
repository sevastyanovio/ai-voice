import CryptoKit
import Foundation

enum SecureHistoryCodec {
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
        if let existingKey = try? readLocalKey() {
            return existingKey
        }

        var rng = SystemRandomNumberGenerator()
        let bytes = (0..<keySize).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        let data = Data(bytes)
        try saveLocalKey(data)
        return data
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
