import SwiftUI
import CoreAudio

enum Page {
    case main, settings, stats
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var audioPlayer: AudioPlayer
    @State private var page: Page = .main
    @State private var showCopied = false

    var body: some View {
        VStack(spacing: 0) {
            switch page {
            case .main: mainPage
            case .settings: settingsPage
            case .stats: statsPage
            }
        }
        .frame(width: 320)
    }

    // MARK: – Main

    @ViewBuilder
    private var mainPage: some View {
        // Record button
        recordButton
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

        if appState.isRecording {
            AudioLevelView(level: CGFloat(appState.audioLevel))
                .frame(height: 24)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        } else if !appState.isTranscribing {
            Text("Double-click to lock mic on")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
        }

        if appState.isTranscribing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Transcribing…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
        }

        if let error = appState.errorMessage {
            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
        }

        if !appState.transcription.isEmpty {
            transcriptionSection
        }

        if !appState.history.records.isEmpty {
            sectionDivider
            historySection
        }

        sectionDivider
        bottomBar
    }

    private var recordButton: some View {
        Button(action: { appState.toggleRecording() }) {
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isRecording ? Color.red : Color.red.opacity(0.85))
                    .frame(width: 10, height: 10)
                    .overlay(
                        appState.isRecording
                            ? RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white)
                                .frame(width: 5, height: 5)
                            : nil
                    )

                if appState.isLockedRecording {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                        Text("Locked — Click to Stop")
                            .font(.system(size: 13, weight: .medium))
                    }
                } else {
                    Text(appState.isRecording ? "Stop Recording" : "Start Recording")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(appState.isRecording ? Color.red.opacity(0.12) : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(appState.isRecording ? Color.red.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var transcriptionSection: some View {
        VStack(spacing: 0) {
            sectionDivider

            Text(appState.transcription)
                .font(.system(size: 12))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            HStack(spacing: 12) {
                Button(action: {
                    appState.copyToClipboard()
                    flashCopied()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(showCopied ? "Copied" : "Copy")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(showCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)

                Button(action: { appState.clear() }) {
                    Text("Clear")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private var historySection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if appState.history.records.count > 3 {
                    Text("\(appState.history.records.count) total")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Button("Clear All") {
                    appState.history.clearAll()
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(appState.history.records.prefix(5)) { record in
                        HistoryRow(
                            record: record,
                            isPlaying: audioPlayer.playingFilename == record.audioFilename && audioPlayer.isPlaying,
                            onPlay: record.audioFilename != nil ? {
                                appState.togglePlayback(record: record)
                            } : nil,
                            onCopy: {
                                appState.copyText(record.text)
                                flashCopied()
                            },
                            onRetranscribe: record.audioFilename != nil ? {
                                appState.retranscribe(record: record)
                            } : nil
                        )
                    }
                }
            }
            .frame(maxHeight: 160)
        }
    }

    // MARK: – Settings

    private var settingsPage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsGroup("API Key") {
                        SecureField("sk-…", text: $appState.apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                        Link("Get key at platform.openai.com",
                             destination: URL(string: "https://platform.openai.com/api-keys")!)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    settingsGroup("Language") {
                        Picker("", selection: $appState.language) {
                            Text("Auto-detect").tag("")
                            Text("Ukrainian").tag("uk")
                            Text("English").tag("en")
                            Text("Russian").tag("ru")
                            Text("German").tag("de")
                            Text("Polish").tag("pl")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    settingsGroup("Push-to-talk") {
                        Picker("", selection: $appState.selectedHotkey) {
                            ForEach(HotkeyChoice.allCases.filter { $0 != .custom }, id: \.self) { choice in
                                Text(choice.displayName).tag(choice)
                            }
                            if appState.selectedHotkey == .custom {
                                Text(HotkeyManager.displayName(forKeyCode: appState.customKeyCode)).tag(HotkeyChoice.custom)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)

                        if appState.isRecordingHotkey {
                            HotkeyRecorderView { keyCode in
                                appState.finishRecordingHotkey(keyCode: keyCode)
                            } onCancel: {
                                appState.cancelRecordingHotkey()
                            }
                        } else {
                            Button(appState.selectedHotkey == .custom
                                   ? "Reassign key…"
                                   : "Assign custom key…") {
                                appState.startRecordingHotkey()
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        }

                        if appState.selectedHotkey != .none && !appState.hasAccessibility {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.orange)
                                    Text("Needs Accessibility")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.orange)
                                    Button("Grant") { appState.requestAccessibility() }
                                        .font(.system(size: 10))
                                    Button("Reset & Re-grant") { appState.resetAndRequestAccessibility() }
                                        .font(.system(size: 10))
                                }
                                Text("If already granted but still showing — rebuild changed the signature. Click Relaunch.")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Button("Relaunch app") { appState.relaunchApp() }
                                    .font(.system(size: 10))
                            }
                        }

                        if appState.selectedHotkey != .none {
                            Text("Hold → speak → release → auto-paste")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if !appState.hasMicPermission {
                        settingsGroup("Microphone") {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.red)
                                Text("Microphone access not granted")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.red)
                            }
                            Text("Grant in System Settings > Privacy & Security > Microphone")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    settingsGroup("Input Device") {
                        Picker("", selection: Binding(
                            get: { appState.selectedDeviceID ?? 0 },
                            set: { appState.selectedDeviceID = $0 == 0 ? nil : $0 }
                        )) {
                            Text("System default").tag(AudioDeviceID(0))
                            ForEach(appState.inputDevices) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)

                        Text("Use built-in mic to avoid BT quality drop")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 360)

            sectionDivider
            bottomBar
        }
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: – Stats

    private var statsPage: some View {
        let h = appState.history
        return VStack(spacing: 0) {
            VStack(spacing: 12) {
                StatRow(icon: "text.word.spacing", label: "Words", value: "\(h.totalWords)")
                StatRow(icon: "number", label: "Transcriptions", value: "\(h.totalTranscriptions)")
                StatRow(icon: "mic", label: "Recording time", value: formatDuration(h.totalRecordingSeconds))
                StatRow(icon: "gauge.with.dots.needle.33percent", label: "Speed", value: h.speakingWPM > 0 ? "\(Int(h.speakingWPM)) WPM" : "—")

                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)

                StatRow(icon: "clock.arrow.trianglehead.counterclockwise.rotate.90", label: "Time saved", value: formatDuration(h.timeSavedSeconds))
                StatRow(icon: "dollarsign.circle", label: "API cost", value: String(format: "$%.3f", h.estimatedCostUSD))

                Text("15 WPM effective typing · Whisper $0.006/min")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)

            sectionDivider
            bottomBar
        }
    }

    // MARK: – Shared

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            if page == .main {
                bottomButton(icon: "chart.bar", label: "Stats") {
                    withAnimation(.easeInOut(duration: 0.15)) { page = .stats }
                }
                bottomButton(icon: "gear", label: "Settings") {
                    appState.refreshInputDevices()
                    withAnimation(.easeInOut(duration: 0.15)) { page = .settings }
                }
                Spacer()
                bottomButton(icon: "power", label: "Quit") {
                    NSApplication.shared.terminate(nil)
                }
            } else {
                bottomButton(icon: "chevron.left", label: "Back") {
                    withAnimation(.easeInOut(duration: 0.15)) { page = .main }
                }
                Spacer()
                bottomButton(icon: "power", label: "Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func bottomButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.00001)) // hit area
            )
        }
        .buttonStyle(.plain)
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins < 60 { return "\(mins)m \(secs)s" }
        let hrs = mins / 60
        let remMins = mins % 60
        return "\(hrs)h \(remMins)m"
    }

    private func flashCopied() {
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopied = false }
    }
}

// MARK: – Audio level bars

struct AudioLevelView: View {
    let level: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<11, id: \.self) { i in
                let dist = abs(CGFloat(i) - 5.0) / 5.0
                let barLevel = max(0.06, level * (1.0 - dist * 0.5) + CGFloat.random(in: -0.03...0.03))

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barColor(barLevel))
                    .frame(width: 3, height: max(3, barLevel * 20))
                    .animation(.easeOut(duration: 0.06), value: level)
            }
        }
    }

    private func barColor(_ level: CGFloat) -> Color {
        if level > 0.7 { return .red.opacity(0.8) }
        if level > 0.4 { return .orange.opacity(0.7) }
        return .green.opacity(0.6)
    }
}

// MARK: – History row

struct HistoryRow: View {
    let record: TranscriptionRecord
    let isPlaying: Bool
    let onPlay: (() -> Void)?
    let onCopy: () -> Void
    let onRetranscribe: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.text)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    Text(record.date, style: .relative)
                    if let dur = record.durationSeconds {
                        Text("·")
                        Text("\(Int(dur))s")
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            if let onPlay {
                Button(action: onPlay) {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(isPlaying ? Color.blue : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(isPlaying ? "Stop" : "Play")
            }

            if let onRetranscribe {
                Button(action: onRetranscribe) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Retranscribe")
            }

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.00001)) // hit area
    }
}

// MARK: – Stat row

struct StatRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 10))
                .frame(width: 16)
                .foregroundStyle(.tertiary)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
        }
    }
}

// MARK: – Hotkey recorder

struct HotkeyRecorderView: NSViewRepresentable {
    let onRecord: (UInt16) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.onRecord = onRecord
        view.onCancel = onCancel
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {}
}

final class HotkeyRecorderNSView: NSView {
    var onRecord: ((UInt16) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        NSColor.controlAccentColor.withAlphaComponent(0.1).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.4).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = "Press any key…" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = text.size(withAttributes: attrs)
        let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        text.draw(at: point, withAttributes: attrs)
    }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 26) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 0x35 { // Escape
            onCancel?()
        } else {
            onRecord?(event.keyCode)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}

