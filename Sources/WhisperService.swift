@preconcurrency import AVFoundation
import Foundation

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
    case audioCompressionFailed
    case audioFileTooLarge(Int64)

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "No API key. Open Settings (⌘,) to add your OpenAI key."
        case .httpError(let code, let message):
            return "API error (\(code)): \(message)"
        case .invalidResponse:
            return "Invalid response from API"
        case .audioCompressionFailed:
            return "Audio is too large and could not be compressed for upload"
        case .audioFileTooLarge(let bytes):
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            return "Audio is too large to transcribe (\(size))"
        }
    }
}

final class WhisperService {
    private let endpoint = "https://api.openai.com/v1/audio/transcriptions"
    private let directUploadLimitBytes = 20 * 1024 * 1024
    private let apiUploadLimitBytes: Int64 = 24 * 1024 * 1024
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    func transcribe(audioURL: URL, apiKey: String, language: String?) async throws -> String {
        guard !apiKey.isEmpty else { throw WhisperError.noApiKey }

        let uploadURL = try await prepareAudioForUpload(audioURL)
        let shouldRemoveUpload = uploadURL != audioURL
        defer {
            if shouldRemoveUpload {
                try? FileManager.default.removeItem(at: uploadURL)
            }
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45

        let audioData = try Data(contentsOf: uploadURL)
        if Int64(audioData.count) > apiUploadLimitBytes {
            throw WhisperError.audioFileTooLarge(Int64(audioData.count))
        }

        var body = Data()

        appendFormField(&body, boundary: boundary, name: "model", value: "whisper-1")

        if let lang = language, !lang.isEmpty {
            appendFormField(&body, boundary: boundary, name: "language", value: lang)
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
        return whisperResponse.text
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
