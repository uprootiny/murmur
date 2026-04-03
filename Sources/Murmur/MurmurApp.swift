import SwiftUI

@main
struct MurmurApp: App {
    @StateObject private var audioEngine = AudioEngine()
    @State private var showSettings = false

    var body: some Scene {
        MenuBarExtra("Murmur", systemImage: audioEngine.isRecording ? "waveform.circle.fill" : "waveform.circle") {
            StatusBarView(audioEngine: audioEngine, showSettings: $showSettings)
        }

        Settings {
            SettingsView(audioEngine: audioEngine)
        }
    }
}
