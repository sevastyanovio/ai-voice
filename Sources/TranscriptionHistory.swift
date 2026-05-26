import Foundation

struct TranscriptionRecord: Codable, Identifiable {
    let id: UUID
    var text: String
    let date: Date
    let durationSeconds: Double?
    var audioFilename: String?
}

final class TranscriptionHistory: ObservableObject {
    @Published private(set) var records: [TranscriptionRecord] = []

    private let encryptedFileURL: URL
    private let legacyFileURL: URL

    init(directory: URL = AIVoiceStorage.appDirectory) {
        AIVoiceStorage.ensureProtectedDirectory(directory)
        encryptedFileURL = directory.appendingPathComponent("history.enc")
        legacyFileURL = directory.appendingPathComponent("history.json")
        load()
    }

    func add(text: String, duration: TimeInterval?, audioFilename: String? = nil) -> TranscriptionRecord {
        let record = TranscriptionRecord(
            id: UUID(),
            text: text,
            date: Date(),
            durationSeconds: duration,
            audioFilename: audioFilename
        )
        records.insert(record, at: 0)
        save()
        return record
    }

    func update(id: UUID, newText: String) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].text = newText
        save()
    }

    func record(id: UUID) -> TranscriptionRecord? {
        records.first { $0.id == id }
    }

    func delete(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        save()
    }

    func clearAll() {
        records.removeAll()
        save()
    }

    // MARK: - Stats

    var totalWords: Int {
        records.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }

    var totalRecordingSeconds: Double {
        records.compactMap(\.durationSeconds).reduce(0, +)
    }

    var totalTranscriptions: Int { records.count }

    /// Average speaking speed in words per minute
    var speakingWPM: Double {
        let mins = totalRecordingSeconds / 60
        guard mins > 0 else { return 0 }
        return Double(totalWords) / mins
    }

    /// Estimated typing time saved (assuming 15 WPM effective output — includes thinking, corrections, formatting)
    var timeSavedSeconds: Double {
        let typingSeconds = Double(totalWords) / 15.0 * 60.0
        return max(0, typingSeconds - totalRecordingSeconds)
    }

    private func load() {
        if let encryptedData = try? Data(contentsOf: encryptedFileURL),
           let decryptedData = try? SecureHistoryCodec.decrypt(encryptedData) {
            decodeRecords(from: decryptedData)
            return
        }

        guard let data = try? Data(contentsOf: legacyFileURL) else { return }
        decodeRecords(from: data)
        if save() {
            try? FileManager.default.removeItem(at: legacyFileURL)
        } else {
            AIVoiceStorage.protectFile(at: legacyFileURL)
        }
    }

    private func decodeRecords(from data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([TranscriptionRecord].self, from: data)) ?? []
    }

    @discardableResult
    private func save() -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records),
              let encryptedData = try? SecureHistoryCodec.encrypt(data) else {
            return false
        }

        do {
            try AIVoiceStorage.writeProtected(encryptedData, to: encryptedFileURL)
        } catch {
            return false
        }

        guard FileManager.default.fileExists(atPath: encryptedFileURL.path) else {
            return false
        }

        try? FileManager.default.removeItem(at: legacyFileURL)
        return true
    }
}
