import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    private let languages = [
        ("", "Auto-detect (best for mixed languages)"),
        ("uk", "Ukrainian"),
        ("en", "English"),
        ("ru", "Russian"),
        ("de", "German"),
        ("fr", "French"),
        ("es", "Spanish"),
        ("pl", "Polish"),
    ]

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Language", selection: $appState.language) {
                    ForEach(languages, id: \.0) { code, label in
                        Text(label).tag(code)
                    }
                }

                Text("Auto-detect works best when mixing Ukrainian + English tech terms")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Transcription", selection: $appState.transcriptionEngine) {
                    ForEach(TranscriptionEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .pickerStyle(.segmented)

                if appState.transcriptionEngine == .openAI {
                    SecureField("OpenAI API Key", text: $appState.apiKey)
                        .textFieldStyle(.roundedBorder)

                    Text("Uses OpenAI Whisper API.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Uses Whisper large-v3 Core ML, the best local model for multilingual dictation.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("First use downloads the model; transcription audio stays on this Mac.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 450, height: 260)
    }
}
