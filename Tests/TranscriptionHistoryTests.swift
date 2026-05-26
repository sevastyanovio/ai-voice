import XCTest
@testable import AIVoice

final class TranscriptionHistoryTests: XCTestCase {
    func testLegacyPlaintextHistoryMigratesToEncryptedStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aivoice-history-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyURL = directory.appendingPathComponent("history.json")
        let encryptedURL = directory.appendingPathComponent("history.enc")
        let legacyRecord = TranscriptionRecord(
            id: UUID(),
            text: "private transcription text",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 2,
            audioFilename: "audio.wav"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([legacyRecord]).write(to: legacyURL)

        let history = TranscriptionHistory(directory: directory)
        XCTAssertEqual(history.records.map(\.text), ["private transcription text"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: encryptedURL.path))

        let encryptedData = try Data(contentsOf: encryptedURL)
        XCTAssertFalse(String(data: encryptedData, encoding: .utf8)?.contains("private transcription text") ?? false)

        let reloadedHistory = TranscriptionHistory(directory: directory)
        XCTAssertEqual(reloadedHistory.records.map(\.text), ["private transcription text"])
    }
}
