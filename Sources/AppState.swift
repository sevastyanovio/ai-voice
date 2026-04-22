import SwiftUI
import AppKit
import CoreGraphics
import CoreAudio
import ApplicationServices

enum RecordingSource {
    case button
    case hotkey
}

@MainActor
final class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var transcription = ""
    @Published var errorMessage: String?

    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: "whisperApiKey") }
    }

    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: "whisperLanguage") }
    }

    @Published var selectedHotkey: HotkeyChoice {
        didSet {
            UserDefaults.standard.set(selectedHotkey.rawValue, forKey: "hotkey")
            configureHotkey()
        }
    }

    @Published var customKeyCode: UInt16 {
        didSet {
            UserDefaults.standard.set(Int(customKeyCode), forKey: "customKeyCode")
            if selectedHotkey == .custom { configureHotkey() }
        }
    }

    @Published var isRecordingHotkey = false

    @Published var selectedDeviceID: AudioDeviceID? {
        didSet {
            if let id = selectedDeviceID,
               let device = inputDevices.first(where: { $0.id == id }) {
                UserDefaults.standard.set(device.name, forKey: "inputDeviceName")
            } else {
                UserDefaults.standard.removeObject(forKey: "inputDeviceName")
            }
            recorder.selectedDeviceID = selectedDeviceID
        }
    }

    @Published var isLockedRecording = false
    @Published var audioLevel: Float = 0
    @Published var hasAccessibility = false
    @Published var hasMicPermission = false
    @Published private(set) var inputDevices: [InputDevice] = []

    let history = TranscriptionHistory()
    let audioPlayer = AudioPlayer()

    var menuBarIcon: String {
        if isRecording { return "waveform.circle.fill" }
        if isTranscribing { return "ellipsis.circle" }
        return "mic"
    }

    private let recorder = AudioRecorder()
    private let whisperService = WhisperService()
    private let hotkeyManager = HotkeyManager()
    private let overlayController = RecordingOverlayController()
    private let statusIslandController = StatusIslandController()
    private var recordingSource: RecordingSource = .button
    private var recordingStartTime: Date?
    private var lockTime: Date?
    private var lastDuration: TimeInterval?
    private var previousApp: NSRunningApplication?
    private var workspaceObserver: Any?

    var currentInputDeviceName: String {
        if let deviceID = selectedDeviceID,
           let device = inputDevices.first(where: { $0.id == deviceID }) {
            return device.name
        }
        return AudioRecorder.defaultInputDeviceName()
    }

    private static let audioDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AIVoice/audio")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        self.apiKey = UserDefaults.standard.string(forKey: "whisperApiKey") ?? ""
        self.language = UserDefaults.standard.string(forKey: "whisperLanguage") ?? ""

        let hotkeyRaw = UserDefaults.standard.string(forKey: "hotkey") ?? HotkeyChoice.none.rawValue
        self.selectedHotkey = HotkeyChoice(rawValue: hotkeyRaw) ?? .none
        self.customKeyCode = UInt16(UserDefaults.standard.integer(forKey: "customKeyCode"))

        refreshInputDevices()

        if let savedName = UserDefaults.standard.string(forKey: "inputDeviceName"),
           let device = inputDevices.first(where: { $0.name == savedName }) {
            self.selectedDeviceID = device.id
            recorder.selectedDeviceID = device.id
        }
        configureHotkey()

        // Prompt for Accessibility on launch (needed for auto-paste)
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        checkAccessibility()

        // Request microphone permission on launch
        hasMicPermission = AudioRecorder.hasMicPermission
        Task {
            let granted = await AudioRecorder.requestMicPermission()
            await MainActor.run { self.hasMicPermission = granted }
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != pid else { return }
            Task { @MainActor in self?.previousApp = app }
        }
    }

    func toggleRecording() {
        if isRecording {
            stopAndTranscribe()
        } else {
            recordingSource = .button
            isLockedRecording = false
            startRecording()
        }
    }

    func copyToClipboard() {
        guard !transcription.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcription, forType: .string)
    }

    func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func clear() {
        transcription = ""
        errorMessage = nil
    }

    func refreshInputDevices() {
        inputDevices = AudioRecorder.availableInputDevices()
    }

    func checkAccessibility() {
        hasAccessibility = AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.checkAccessibility()
        }
    }

    func startRecordingHotkey() {
        hotkeyManager.stop()
        isRecordingHotkey = true
    }

    func finishRecordingHotkey(keyCode: UInt16) {
        isRecordingHotkey = false
        customKeyCode = keyCode
        selectedHotkey = .custom
    }

    func cancelRecordingHotkey() {
        isRecordingHotkey = false
        configureHotkey()
    }

    private func configureHotkey() {
        hotkeyManager.stop()
        hotkeyManager.selectedHotkey = selectedHotkey
        hotkeyManager.customKeyCode = customKeyCode

        hotkeyManager.onKeyDown = { [weak self] in
            Task { @MainActor in
                guard let self else { return }

                if self.isRecording && self.isLockedRecording {
                    // Cooldown — ignore presses for 0.8s after locking
                    if let lt = self.lockTime, Date().timeIntervalSince(lt) < 0.8 {
    
                        return
                    }

                    self.stopAndTranscribe()
                    return
                }

                // Debounce — don't start new recording if one just stopped
                guard !self.isRecording, !self.isTranscribing else { return }
                self.recordingSource = .hotkey
                self.capturePreviousAppFromFrontmost()
                self.startRecording()
            }
        }

        hotkeyManager.onKeyUp = { [weak self] in
            Task { @MainActor in
                guard let self, self.isRecording, self.recordingSource == .hotkey else { return }

                // If locked, ignore release
                if self.isLockedRecording { return }

                // Quick tap (< 0.4s hold) = lock mode
                let holdDuration = self.recordingStartTime.map { Date().timeIntervalSince($0) } ?? 999
                if holdDuration < 0.4 {

                    self.isLockedRecording = true
                    self.lockTime = Date()
                    self.statusIslandController.updateMode(.recording(deviceName: self.currentInputDeviceName, locked: true))
                    return
                }

                self.stopAndTranscribe()
            }
        }

        hotkeyManager.start()
    }

    private func startRecording() {
        recorder.onAudioLevel = { [weak self] level in
            DispatchQueue.main.async {
                guard let self else { return }
                self.audioLevel = level
                self.overlayController.state.setRaw(level)
            }
        }

        // Stop any playback before recording
        audioPlayer.stop()

        // If mic permission not yet granted, request it first
        guard AudioRecorder.hasMicPermission else {
            Task {
                let granted = await AudioRecorder.requestMicPermission()
                hasMicPermission = granted
                if granted {
                    startRecording() // retry now that we have permission
                } else {
                    errorMessage = "Microphone access denied — grant in System Settings > Privacy > Microphone"
                }
            }
            return
        }

        do {
            try recorder.startRecording()
            isRecording = true
            errorMessage = nil
            recordingStartTime = Date()
            overlayController.show()
            statusIslandController.show(mode: .recording(deviceName: currentInputDeviceName, locked: false))
        } catch {
            errorMessage = "Mic error: \(error.localizedDescription)"
        }
    }

    private func stopAndTranscribe() {
        isRecording = false
        isLockedRecording = false
        audioLevel = 0
        overlayController.state.setRaw(0)
        overlayController.dismiss()
        recorder.onAudioLevel = nil

        guard let result = recorder.stopRecording() else {
            errorMessage = "No audio captured"
            statusIslandController.dismiss()
            return
        }

        lastDuration = result.duration

        if result.duration < 0.3 {
            errorMessage = "Too short — hold longer"
            statusIslandController.dismiss()
            try? FileManager.default.removeItem(at: result.url)
            return
        }

        // Save audio permanently for retranscription
        let filename = "\(UUID().uuidString).wav"
        let savedURL = Self.audioDir.appendingPathComponent(filename)
        try? FileManager.default.copyItem(at: result.url, to: savedURL)
        try? FileManager.default.removeItem(at: result.url)

        isTranscribing = true
        errorMessage = nil
        statusIslandController.show(mode: .transcribing)

        Task {
            do {
                let lang = language.isEmpty ? nil : language
                let text = try await whisperService.transcribe(
                    audioURL: savedURL,
                    apiKey: apiKey,
                    language: lang
                )

                transcription = text
                history.add(text: text, duration: lastDuration, audioFilename: filename)

                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                simulatePaste()
            } catch {
                // Persist the recording in history with a placeholder so the user
                // can retry transcription from the UI instead of losing it.
                errorMessage = error.localizedDescription
                history.add(
                    text: "[Transcription failed — click retry] \(error.localizedDescription)",
                    duration: lastDuration,
                    audioFilename: filename
                )
            }
            isTranscribing = false
            statusIslandController.dismiss()
        }
    }

    func togglePlayback(record: TranscriptionRecord) {
        guard let filename = record.audioFilename else { return }
        let audioURL = Self.audioDir.appendingPathComponent(filename)
        audioPlayer.toggle(url: audioURL, filename: filename)
    }

    func retranscribe(record: TranscriptionRecord) {
        guard let filename = record.audioFilename else {
            errorMessage = "No audio file saved for this recording"
            return
        }
        let audioURL = Self.audioDir.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            errorMessage = "Audio file no longer exists"
            return
        }

        isTranscribing = true
        errorMessage = nil
        statusIslandController.show(mode: .transcribing)

        Task {
            do {
                let lang = language.isEmpty ? nil : language
                let text = try await whisperService.transcribe(
                    audioURL: audioURL,
                    apiKey: apiKey,
                    language: lang
                )

                transcription = text
                history.update(id: record.id, newText: text)

                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } catch {
                errorMessage = error.localizedDescription
            }
            isTranscribing = false
            statusIslandController.dismiss()
        }
    }

    private func capturePreviousAppFromFrontmost() {
        let pid = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != pid {
            previousApp = front
        }
    }

    private func simulatePaste() {
        guard AXIsProcessTrusted() else {
            errorMessage = "Restart app after granting Accessibility"
            return
        }

        previousApp?.activate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let src = CGEventSource(stateID: .combinedSessionState)
            let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            vDown?.flags = .maskCommand
            vUp?.flags = .maskCommand
            vDown?.post(tap: .cgSessionEventTap)
            vUp?.post(tap: .cgSessionEventTap)
        }
    }
}
