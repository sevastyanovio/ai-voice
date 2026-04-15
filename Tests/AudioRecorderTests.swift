import XCTest
@testable import AIVoice

final class AudioRecorderTests: XCTestCase {

    func testMicPermissionPropertyDoesNotCrash() {
        // Just verify the static property is accessible (value depends on TCC state)
        _ = AudioRecorder.hasMicPermission
    }

    func testStartRecordingWithoutPermissionThrows() {
        // When mic permission is denied, startRecording should throw
        // This test only verifies the error type when permission is not granted
        guard !AudioRecorder.hasMicPermission else {
            // Permission already granted in CI/test env — skip
            return
        }

        let recorder = AudioRecorder()
        XCTAssertThrowsError(try recorder.startRecording()) { error in
            XCTAssertTrue(error is AudioRecorderError)
        }
    }

    func testAvailableInputDevicesReturnsArray() {
        let devices = AudioRecorder.availableInputDevices()
        // Just verify it returns without crashing — count depends on hardware
        XCTAssertTrue(devices is [InputDevice])
    }

    func testDefaultInputDeviceNameReturnsNonEmpty() {
        let name = AudioRecorder.defaultInputDeviceName()
        XCTAssertFalse(name.isEmpty)
    }

    func testStopRecordingWithoutStartReturnsNil() {
        let recorder = AudioRecorder()
        let result = recorder.stopRecording()
        XCTAssertNil(result)
    }
}
