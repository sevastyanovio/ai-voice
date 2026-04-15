import AVFoundation
import CoreAudio

struct InputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

enum AudioRecorderError: LocalizedError {
    case microphonePermissionDenied

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access denied — grant in System Settings > Privacy > Microphone"
        }
    }
}

final class AudioRecorder {
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var recordingStart: Date?

    var selectedDeviceID: AudioDeviceID?
    var onAudioLevel: ((Float) -> Void)?

    /// Request microphone permission. Returns true if granted.
    static func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static var hasMicPermission: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    func startRecording() throws {
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw AudioRecorderError.microphonePermissionDenied
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicenote_\(UUID().uuidString).wav")

        let engine = AVAudioEngine()

        if let deviceID = selectedDeviceID {
            try setInputDevice(deviceID, on: engine)
        }

        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        let tapFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hwFormat.sampleRate,
            channels: 1,
            interleaved: false
        )!

        let wavSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: hwFormat.sampleRate,
            AVNumberOfChannelsKey: 1
        ]

        audioFile = try AVAudioFile(
            forWriting: url,
            settings: wavSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<count { sum += channelData[i] * channelData[i] }
            let rms = sqrt(sum / Float(count))
            let normalized = min(1.0, rms * 10)
            self?.onAudioLevel?(normalized)
        }

        engine.prepare()
        try engine.start()

        self.engine = engine
        self.recordingURL = url
        self.recordingStart = Date()
    }

    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        audioFile = nil

        guard let url = recordingURL else { return nil }
        let duration = recordingStart.map { Date().timeIntervalSince($0) } ?? 0
        recordingURL = nil
        recordingStart = nil
        return (url, duration)
    }

    private func setInputDevice(_ deviceID: AudioDeviceID, on engine: AVAudioEngine) throws {
        var id = deviceID
        let status = AudioUnitSetProperty(
            engine.inputNode.audioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func availableInputDevices() -> [InputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return [] }

        return deviceIDs.compactMap { deviceID in
            guard hasInputChannels(deviceID) else { return nil }
            guard let name = deviceName(deviceID) else { return nil }
            return InputDevice(id: deviceID, name: name)
        }
    }

    static func defaultInputDeviceName() -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr else { return "Microphone" }
        return deviceName(deviceID) ?? "Microphone"
    }

    private static func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else {
            return false
        }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferList.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList) == noErr else {
            return false
        }

        let channels = UnsafeMutableAudioBufferListPointer(bufferList)
            .reduce(0) { $0 + Int($1.mNumberChannels) }
        return channels > 0
    }

    static func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name) == noErr else {
            return nil
        }
        return name as String
    }
}
