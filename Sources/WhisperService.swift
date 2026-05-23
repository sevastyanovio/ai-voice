@preconcurrency import AVFoundation
import Foundation
import WhisperKit

enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case openAI = "openAI"
    case onDevice = "onDevice"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:
            return "Whisper OAI"
        case .onDevice:
            return "Local Model"
        }
    }
}

enum CloudTranscriptionModel: String, CaseIterable, Identifiable {
    case whisper = "whisper-1"

    var id: String { rawValue }
    var displayName: String { "Whisper OAI" }
    var detail: String { "OpenAI Whisper API" }
}

enum LocalTranscriptionModel: String, CaseIterable, Identifiable {
    case bestAccuracy = "large-v3-v20240930_626MB"
    case fastLarge = "large-v3-v20240930_turbo_632MB"
    case small = "small_216MB"
    case base = "base"
    case tiny = "tiny"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bestAccuracy:
            return "Best Accuracy"
        case .fastLarge:
            return "Fast Large"
        case .small:
            return "Small"
        case .base:
            return "Base"
        case .tiny:
            return "Tiny"
        }
    }

    var detail: String {
        switch self {
        case .bestAccuracy:
            return "Whisper large-v3 Core ML, recommended for multilingual dictation"
        case .fastLarge:
            return "Large-v3 turbo, faster with slightly lower accuracy"
        case .small:
            return "Good for quick daily dictation on slower Macs"
        case .base:
            return "Lightweight fallback"
        case .tiny:
            return "Fastest model for testing"
        }
    }

    var whisperKitModelName: String { rawValue }
}

struct WhisperResponse: Decodable {
    let text: String
}

struct WhisperErrorResponse: Decodable {
    let error: WhisperErrorDetail
}

struct WhisperErrorDetail: Decodable {
    let message: String
}

enum WhisperError: LocalizedError {
    case noApiKey
    case httpError(Int, String)
    case invalidResponse
    case emptyTranscription
    case audioCompressionFailed
    case audioFileTooLarge(Int64)

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "Add an OpenAI API key or switch Transcription to Local Model."
        case .httpError(let code, let message):
            return "Transcription API error (\(code)): \(message)"
        case .invalidResponse:
            return "Invalid transcription response"
        case .emptyTranscription:
            return "No speech detected"
        case .audioCompressionFailed:
            return "Audio is too large and could not be compressed for upload"
        case .audioFileTooLarge(let bytes):
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            return "Audio is too large to transcribe (\(size))"
        }
    }
}

actor WhisperService {
    static let bestCloudModel: CloudTranscriptionModel = .whisper
    static let bestLocalModel: LocalTranscriptionModel = .bestAccuracy

    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private let directUploadLimitBytes = 20 * 1024 * 1024
    private let apiUploadLimitBytes: Int64 = 24 * 1024 * 1024
    private let session: URLSession
    private var loadedModel: LocalTranscriptionModel?
    private var pipe: WhisperKit?

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    func transcribe(
        audioURL: URL,
        engine: TranscriptionEngine,
        apiKey: String,
        language: String?
    ) async throws -> String {
        switch engine {
        case .openAI:
            return try await transcribeWithOpenAI(
                audioURL: audioURL,
                apiKey: apiKey,
                model: Self.bestCloudModel,
                language: language
            )
        case .onDevice:
            return try await transcribeOnDevice(
                audioURL: audioURL,
                model: Self.bestLocalModel,
                language: language
            )
        }
    }

    private func transcribeOnDevice(
        audioURL: URL,
        model: LocalTranscriptionModel,
        language: String?
    ) async throws -> String {
        let whisperKit = try await pipeline(for: model)
        let options = DecodingOptions(
            language: language,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )
        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { throw WhisperError.emptyTranscription }
        return text
    }

    private func transcribeWithOpenAI(
        audioURL: URL,
        apiKey: String,
        model: CloudTranscriptionModel,
        language: String?
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw WhisperError.noApiKey }

        let uploadURL = try await prepareAudioForUpload(audioURL)
        let shouldRemoveUpload = uploadURL != audioURL
        defer {
            if shouldRemoveUpload {
                try? FileManager.default.removeItem(at: uploadURL)
            }
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45

        let audioData = try Data(contentsOf: uploadURL)
        if Int64(audioData.count) > apiUploadLimitBytes {
            throw WhisperError.audioFileTooLarge(Int64(audioData.count))
        }

        var body = Data()
        appendFormField(&body, boundary: boundary, name: "model", value: model.rawValue)

        if let language, !language.isEmpty {
            appendFormField(&body, boundary: boundary, name: "language", value: language)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        let filename = Self.uploadFilename(for: uploadURL)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(Self.mimeType(for: uploadURL))\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhisperError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(WhisperErrorResponse.self, from: data) {
                throw WhisperError.httpError(httpResponse.statusCode, errorResponse.error.message)
            }
            throw WhisperError.httpError(httpResponse.statusCode, "Unknown error")
        }

        let whisperResponse = try JSONDecoder().decode(WhisperResponse.self, from: data)
        let text = whisperResponse.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw WhisperError.emptyTranscription }
        return text
    }

    private func pipeline(for model: LocalTranscriptionModel) async throws -> WhisperKit {
        if let pipe, loadedModel == model {
            return pipe
        }

        let config = WhisperKitConfig(
            model: model.whisperKitModelName,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: true
        )
        let newPipe = try await WhisperKit(config)
        loadedModel = model
        pipe = newPipe
        return newPipe
    }

    private func appendFormField(_ body: inout Data, boundary: String, name: String, value: String) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }

    private func prepareAudioForUpload(_ audioURL: URL) async throws -> URL {
        let values = try audioURL.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize, fileSize > directUploadLimitBytes else {
            return audioURL
        }

        return try await compressedM4A(from: audioURL)
    }

    private func compressedM4A(from audioURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: audioURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw WhisperError.audioCompressionFailed
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper_upload_\(UUID().uuidString).m4a")

        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        exporter.shouldOptimizeForNetworkUse = true

        let exporterBox = ExportSessionBox(exporter)
        return try await withCheckedThrowingContinuation { continuation in
            exporterBox.session.exportAsynchronously {
                switch exporterBox.session.status {
                case .completed:
                    continuation.resume(returning: outputURL)
                case .failed, .cancelled:
                    try? FileManager.default.removeItem(at: outputURL)
                    continuation.resume(
                        throwing: exporterBox.session.error ?? WhisperError.audioCompressionFailed
                    )
                default:
                    try? FileManager.default.removeItem(at: outputURL)
                    continuation.resume(throwing: WhisperError.audioCompressionFailed)
                }
            }
        }
    }

    static func uploadFilename(for url: URL) -> String {
        let ext = url.pathExtension.isEmpty ? "wav" : url.pathExtension
        return "audio.\(ext)"
    }

    static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a":
            return "audio/mp4"
        case "mp3":
            return "audio/mpeg"
        case "webm":
            return "audio/webm"
        case "wav", "wave":
            return "audio/wav"
        default:
            return "application/octet-stream"
        }
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}
