import AVFoundation
import CoreAudio

struct InputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

enum AudioRecorderError: LocalizedError {
    case microphonePermissionDenied
    case inputDeviceUnavailable
    case inputFormatUnavailable
    case recordingAlreadyInProgress

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access denied — grant in System Settings > Privacy > Microphone"
        case .inputDeviceUnavailable:
            return "Selected microphone is unavailable — reconnect it or choose another input device"
        case .inputFormatUnavailable:
            return "Microphone is not ready yet — try again in a moment"
        case .recordingAlreadyInProgress:
            return "A recording is already in progress"
        }
    }
}

final class AudioRecorder {
    /// AVAudioEngine invokes its tap on an audio thread while AppState changes
    /// the handler and tears the recording down on the main thread. Keep the
    /// shared references behind one lock so ARC never races on a closure or
    /// AVAudioFile reference.
    private let stateLock = NSLock()
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var recordingStart: Date?
    private var isAcceptingBuffers = false
    private var storedSelectedDeviceID: AudioDeviceID?
    private var storedAudioLevelHandler: ((Float) -> Void)?

    var selectedDeviceID: AudioDeviceID? {
        get { withStateLock { storedSelectedDeviceID } }
        set { withStateLock { storedSelectedDeviceID = newValue } }
    }

    var onAudioLevel: ((Float) -> Void)? {
        get { withStateLock { storedAudioLevelHandler } }
        set { withStateLock { storedAudioLevelHandler = newValue } }
    }

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

        guard engine == nil else {
            throw AudioRecorderError.recordingAlreadyInProgress
        }

        let selectedDeviceID = selectedDeviceID
        let deviceID = selectedDeviceID ?? Self.systemDefaultInputDeviceID()
        guard deviceID != 0, Self.hasInputChannels(deviceID) else {
            throw AudioRecorderError.inputDeviceUnavailable
        }

        do {
            try startRecordingAttempt(selectedDeviceID: selectedDeviceID)
        } catch {
            // Bluetooth and USB microphones occasionally report an unavailable
            // format immediately after wake. Recreate the input audio unit once
            // after a short settle period instead of requiring a System Settings
            // volume adjustment to wake the device.
            Thread.sleep(forTimeInterval: 0.12)
            try startRecordingAttempt(selectedDeviceID: selectedDeviceID)
        }
    }

    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        let activeEngine = engine
        engine = nil

        // Prevent a concurrent tap invocation from retaining or writing through
        // an object that the main thread is about to release or move.
        withStateLock {
            isAcceptingBuffers = false
            storedAudioLevelHandler = nil
        }

        activeEngine?.inputNode.removeTap(onBus: 0)
        activeEngine?.stop()

        withStateLock {
            audioFile = nil
        }

        guard let url = recordingURL else { return nil }
        let duration = recordingStart.map { Date().timeIntervalSince($0) } ?? 0
        recordingURL = nil
        recordingStart = nil
        return (url, duration)
    }

    private func startRecordingAttempt(selectedDeviceID: AudioDeviceID?) throws {
        let url = AIVoiceStorage.recordingStagingDirectory
            .appendingPathComponent("voicenote_\(UUID().uuidString).wav")
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        var tapInstalled = false

        do {
            if let selectedDeviceID {
                try setInputDevice(selectedDeviceID, on: engine)
            }

            engine.prepare()

            // Apple documents inputFormat(forBus:) as the hardware format to
            // validate before recording. A zero sample rate or channel count can
            // otherwise produce an AVAudioEngine exception rather than a throw.
            let hardwareFormat = inputNode.inputFormat(forBus: 0)
            guard Self.isUsableInputFormat(
                sampleRate: hardwareFormat.sampleRate,
                channelCount: hardwareFormat.channelCount
            ) else {
                throw AudioRecorderError.inputFormatUnavailable
            }

            let fileFormat = inputNode.outputFormat(forBus: 0)
            guard Self.isUsableInputFormat(
                sampleRate: fileFormat.sampleRate,
                channelCount: fileFormat.channelCount
            ) else {
                throw AudioRecorderError.inputFormatUnavailable
            }

            let wavSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVSampleRateKey: fileFormat.sampleRate,
                AVNumberOfChannelsKey: fileFormat.channelCount
            ]

            let file = try AVAudioFile(
                forWriting: url,
                settings: wavSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            AIVoiceStorage.protectFile(at: url)

            withStateLock {
                audioFile = file
                isAcceptingBuffers = true
            }

            // Passing nil uses AVAudioEngine's active device format. Supplying a
            // separately queried CoreAudio format can force a stale Bluetooth
            // format onto the tap and either fail or produce silent audio.
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
                self?.consume(buffer)
            }
            tapInstalled = true

            try engine.start()
            guard engine.isRunning else {
                throw AudioRecorderError.inputDeviceUnavailable
            }

            self.engine = engine
            self.recordingURL = url
            self.recordingStart = Date()
        } catch {
            if tapInstalled {
                inputNode.removeTap(onBus: 0)
            }
            engine.stop()
            withStateLock {
                isAcceptingBuffers = false
                audioFile = nil
            }
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        let audioLevelHandler: ((Float) -> Void)? = withStateLock {
            guard isAcceptingBuffers, let audioFile else { return nil }
            try? audioFile.write(from: buffer)
            return storedAudioLevelHandler
        }

        guard let audioLevelHandler,
              let channelData = buffer.floatChannelData?[0],
              buffer.frameLength > 0 else {
            return
        }

        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += channelData[i] * channelData[i] }
        let rms = sqrt(sum / Float(count))
        audioLevelHandler(min(1.0, rms * 10))
    }

    private func withStateLock<T>(_ operation: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return operation()
    }

    private func setInputDevice(_ deviceID: AudioDeviceID, on engine: AVAudioEngine) throws {
        var id = deviceID
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw AudioRecorderError.inputDeviceUnavailable
        }
        let status = AudioUnitSetProperty(
            audioUnit,
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
            let uid = deviceUID(deviceID) ?? "coreaudio-device-\(deviceID)"
            return InputDevice(id: deviceID, uid: uid, name: name)
        }
    }

    static func defaultInputDeviceName() -> String {
        let deviceID = systemDefaultInputDeviceID()
        return deviceName(deviceID) ?? "Microphone"
    }

    static func systemDefaultInputDeviceID() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr else { return 0 }
        return deviceID
    }

    static func deviceSampleRate(_ deviceID: AudioDeviceID) -> Float64? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate) == noErr,
              rate > 0 else { return nil }
        return rate
    }

    static func isUsableInputFormat(sampleRate: Double, channelCount: AVAudioChannelCount) -> Bool {
        sampleRate.isFinite && sampleRate > 0 && channelCount > 0
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

        // Output-only, aggregate, and temporarily disconnected devices can
        // legitimately return an empty input-stream configuration. The old code
        // allocated zero AudioBufferLists and then read the uninitialized header,
        // which corrupted memory while Settings enumerated devices.
        let headerSize = MemoryLayout<UInt32>.size
        guard Int(size) >= headerSize else { return false }

        let byteCount = Int(size)
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        storage.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
        defer { storage.deallocate() }

        let bufferList = storage.assumingMemoryBound(to: AudioBufferList.self)
        var returnedSize = size
        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &returnedSize,
            bufferList
        ) == noErr else {
            return false
        }

        guard let buffersOffset = MemoryLayout<AudioBufferList>.offset(of: \AudioBufferList.mBuffers),
              Int(returnedSize) >= buffersOffset else {
            return false
        }

        let bufferCount = Int(bufferList.pointee.mNumberBuffers)
        let maxBufferCount = (Int(returnedSize) - buffersOffset) / MemoryLayout<AudioBuffer>.stride
        guard bufferCount <= maxBufferCount else { return false }

        let channels = UnsafeMutableAudioBufferListPointer(bufferList)
            .prefix(bufferCount)
            .reduce(0) { $0 + Int($1.mNumberChannels) }
        return channels > 0
    }

    static func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let namePointer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        namePointer.initialize(to: nil)
        defer {
            namePointer.deinitialize(count: 1)
            namePointer.deallocate()
        }

        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, namePointer) == noErr,
              let name = namePointer.pointee else {
            return nil
        }
        return name as String
    }

    static func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let uidPointer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        uidPointer.initialize(to: nil)
        defer {
            uidPointer.deinitialize(count: 1)
            uidPointer.deallocate()
        }

        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, uidPointer) == noErr,
              let uid = uidPointer.pointee else {
            return nil
        }
        return uid as String
    }
}
