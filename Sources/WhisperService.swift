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

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "No API key. Open Settings (⌘,) to add your OpenAI key."
        case .httpError(let code, let message):
            return "API error (\(code)): \(message)"
        case .invalidResponse:
            return "Invalid response from API"
        }
    }
}

final class WhisperService {
    private let endpoint = "https://api.openai.com/v1/audio/transcriptions"

    func transcribe(audioURL: URL, apiKey: String, language: String?) async throws -> String {
        guard !apiKey.isEmpty else { throw WhisperError.noApiKey }

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)

        var body = Data()

        appendFormField(&body, boundary: boundary, name: "model", value: "whisper-1")

        if let lang = language, !lang.isEmpty {
            appendFormField(&body, boundary: boundary, name: "language", value: lang)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

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
}
