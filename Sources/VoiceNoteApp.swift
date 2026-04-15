import SwiftUI

@main
struct VoiceNoteApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            ContentView(audioPlayer: appState.audioPlayer)
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
