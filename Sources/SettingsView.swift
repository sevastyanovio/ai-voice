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
            Section("OpenAI API") {
                SecureField("API Key", text: $appState.apiKey)
                    .textFieldStyle(.roundedBorder)

                Link(
                    "Get API key at platform.openai.com",
                    destination: URL(string: "https://platform.openai.com/api-keys")!
                )
                .font(.caption)
            }

            Section("Transcription") {
                Picker("Language", selection: $appState.language) {
                    ForEach(languages, id: \.0) { code, label in
                        Text(label).tag(code)
                    }
                }

                Text("Auto-detect works best when mixing Ukrainian + English tech terms")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 450, height: 280)
    }
}
