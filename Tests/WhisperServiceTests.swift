import XCTest
@testable import AIVoice

final class WhisperServiceTests: XCTestCase {
    func testUploadFilenameDefaultsToWavWhenExtensionIsMissing() {
        let url = URL(fileURLWithPath: "/tmp/audio")
        XCTAssertEqual(WhisperService.uploadFilename(for: url), "audio.wav")
    }

    func testMimeTypeMatchesSupportedAudioExtensions() {
        XCTAssertEqual(WhisperService.mimeType(for: URL(fileURLWithPath: "/tmp/audio.wav")), "audio/wav")
        XCTAssertEqual(WhisperService.mimeType(for: URL(fileURLWithPath: "/tmp/audio.m4a")), "audio/mp4")
        XCTAssertEqual(WhisperService.mimeType(for: URL(fileURLWithPath: "/tmp/audio.mp3")), "audio/mpeg")
        XCTAssertEqual(WhisperService.mimeType(for: URL(fileURLWithPath: "/tmp/audio.webm")), "audio/webm")
    }
}
