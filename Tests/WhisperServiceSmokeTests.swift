import XCTest
@testable import AIVoice

final class WhisperServiceSmokeTests: XCTestCase {
    func testBestLocalModelTranscribesLocalAudioWhenSmokeAudioIsProvided() async throws {
        guard let audioPath = ProcessInfo.processInfo.environment["AIVOICE_SMOKE_AUDIO"] else {
            throw XCTSkip("Set AIVOICE_SMOKE_AUDIO to run the on-device transcription smoke test")
        }

        let audioURL = URL(fileURLWithPath: audioPath)
        let service = WhisperService()
        let text = try await service.transcribe(
            audioURL: audioURL,
            engine: .onDevice,
            apiKey: "",
            language: "en"
        ).lowercased()

        XCTAssertTrue(
            text.contains("local") || text.contains("whisper") || text.contains("voice"),
            "Unexpected transcript: \(text)"
        )
    }
}
