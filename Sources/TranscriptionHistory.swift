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

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("AIVoice")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func add(text: String, duration: TimeInterval?, audioFilename: String? = nil) {
        let record = TranscriptionRecord(
            id: UUID(),
            text: text,
            date: Date(),
            durationSeconds: duration,
            audioFilename: audioFilename
        )
        records.insert(record, at: 0)
        save()
    }

    func update(id: UUID, newText: String) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].text = newText
        save()
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

    /// Whisper API cost: $0.006 per minute
    var estimatedCostUSD: Double {
        totalRecordingSeconds / 60.0 * 0.006
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([TranscriptionRecord].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
