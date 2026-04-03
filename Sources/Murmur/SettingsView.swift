import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var audioEngine: AudioEngine
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            // Audio Quality
            Section("Audio") {
                Picker("Quality", selection: $audioEngine.quality) {
                    ForEach(AudioQuality.allCases) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }
                .pickerStyle(.segmented)

                Stepper(
                    "Segment duration: \(audioEngine.maxSegmentMinutes) min",
                    value: $audioEngine.maxSegmentMinutes,
                    in: 5...120,
                    step: 5
                )
            }

            // Storage
            Section("Storage") {
                HStack {
                    Text(audioEngine.storageURL.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Choose...") {
                        chooseStorageLocation()
                    }
                }

                Button("Reveal in Finder") {
                    audioEngine.openRecordingsFolder()
                }
            }

            // System
            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 320)
        .onAppear {
            launchAtLogin = currentLaunchAtLoginState()
        }
    }

    // MARK: - Storage Location Picker

    private func chooseStorageLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            audioEngine.storageURL = url
        }
    }

    // MARK: - Launch at Login

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[Murmur] Launch at login error: \(error.localizedDescription)")
        }
    }

    private func currentLaunchAtLoginState() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }
}
