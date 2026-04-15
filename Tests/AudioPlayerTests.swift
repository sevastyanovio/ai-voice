import XCTest
import AVFoundation
@testable import VoiceNote

@MainActor
final class AudioPlayerTests: XCTestCase {

    func testInitialState() {
        let player = AudioPlayer()
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.playingFilename)
    }

    func testPlayNonexistentFileDoesNotCrash() {
        let player = AudioPlayer()
        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID()).wav")
        player.play(url: url, filename: "nonexistent.wav")
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.playingFilename)
    }

    func testStopWhenNotPlaying() {
        let player = AudioPlayer()
        player.stop()
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.playingFilename)
    }

    func testPlayValidWavFile() throws {
        let player = AudioPlayer()
        let url = try createTestWavFile()
        defer { try? FileManager.default.removeItem(at: url) }

        player.play(url: url, filename: "test.wav")
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.playingFilename, "test.wav")

        player.stop()
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.playingFilename)
    }

    func testToggleStartsAndStops() throws {
        let player = AudioPlayer()
        let url = try createTestWavFile()
        defer { try? FileManager.default.removeItem(at: url) }

        player.toggle(url: url, filename: "test.wav")
        XCTAssertTrue(player.isPlaying)

        player.toggle(url: url, filename: "test.wav")
        XCTAssertFalse(player.isPlaying)
    }

    func testToggleDifferentFileStopsPrevious() throws {
        let player = AudioPlayer()
        let url1 = try createTestWavFile()
        let url2 = try createTestWavFile()
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }

        player.toggle(url: url1, filename: "a.wav")
        XCTAssertEqual(player.playingFilename, "a.wav")

        player.toggle(url: url2, filename: "b.wav")
        XCTAssertEqual(player.playingFilename, "b.wav")
        XCTAssertTrue(player.isPlaying)
    }

    // MARK: - Helpers

    private func createTestWavFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).wav")

        // Create a minimal valid WAV file (44-byte header + 1 second of silence at 44100 Hz, 16-bit mono)
        let sampleRate: UInt32 = 44100
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let numSamples: UInt32 = sampleRate // 1 second
        let dataSize = numSamples * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let fileSize = 36 + dataSize

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // chunk size
        data.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })  // PCM
        data.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        let byteRate = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        data.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        let blockAlign = numChannels * (bitsPerSample / 8)
        data.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        data.append(contentsOf: "data".utf8)
        data.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        data.append(Data(count: Int(dataSize))) // silence

        try data.write(to: url)
        return url
    }
}
