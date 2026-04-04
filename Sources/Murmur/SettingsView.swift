import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var screenCapture: ScreenCapture
    @ObservedObject var ocrEngine: OCREngine
    @ObservedObject var transcriptionEngine: TranscriptionEngine
    @ObservedObject var ringBuffer: RingBuffer

    @State private var launchAtLogin = false
    @State private var bufferMinutes: Double = 60
    @State private var maxDiskGB: Double = 1.0
    @State private var screenCaptureEnabled: Bool = false
    @State private var captureFrameRate: Double = 2.0

    var body: some View {
        TabView {
            // Audio tab
            audioSettingsTab
                .tabItem {
                    Label("Audio", systemImage: "mic")
                }

            // Screen Capture tab
            screenCaptureSettingsTab
                .tabItem {
                    Label("Screen", systemImage: "rectangle.on.rectangle")
                }

            // Buffer tab
            bufferSettingsTab
                .tabItem {
                    Label("Buffer", systemImage: "circle.dotted.circle")
                }

            // Processing tab
            processingSettingsTab
                .tabItem {
                    Label("Processing", systemImage: "cpu")
                }

            // System tab
            systemSettingsTab
                .tabItem {
                    Label("System", systemImage: "gear")
                }
        }
        .frame(width: 480, height: 400)
        .onAppear {
            launchAtLogin = currentLaunchAtLoginState()
            bufferMinutes = Double(ringBuffer.maxChunks) * ringBuffer.chunkDurationSeconds / 60.0
            maxDiskGB = Double(ringBuffer.maxDiskBytes) / 1_073_741_824.0
            screenCaptureEnabled = screenCapture.isCapturing
            captureFrameRate = screenCapture.frameRate.rawValue
        }
    }

    // MARK: - Audio Settings

    private var audioSettingsTab: some View {
        Form {
            Section("Audio Quality") {
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
        }
        .formStyle(.grouped)
    }

    // MARK: - Screen Capture Settings

    private var screenCaptureSettingsTab: some View {
        Form {
            Section("Screen Capture") {
                Toggle("Enable screen capture", isOn: $screenCaptureEnabled)
                    .onChange(of: screenCaptureEnabled) { _, newValue in
                        Task {
                            if newValue {
                                try? await screenCapture.startCapture()
                            } else {
                                await screenCapture.stopCapture()
                            }
                        }
                    }

                if screenCaptureEnabled {
                    HStack {
                        Text("Frame rate")
                        Spacer()
                        Picker("", selection: $captureFrameRate) {
                            Text("2 fps (background)").tag(2.0)
                            Text("5 fps").tag(5.0)
                            Text("10 fps").tag(10.0)
                            Text("30 fps (review)").tag(30.0)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                    }

                    if let lastFrame = screenCapture.lastFrameTime {
                        HStack {
                            Text("Last frame")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(lastFrame, style: .relative)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("Permissions") {
                HStack {
                    Image(systemName: "lock.shield")
                    Text("Screen recording permission is required.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Buffer Settings

    private var bufferSettingsTab: some View {
        Form {
            Section("Ring Buffer") {
                VStack(alignment: .leading) {
                    Text("Buffer duration: \(Int(bufferMinutes)) min")
                    Slider(value: $bufferMinutes, in: 5...60, step: 5) {
                        Text("Buffer duration")
                    }
                    Text("Stores up to \(Int(bufferMinutes)) minutes of recordings in a circular buffer.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading) {
                    Text("Max disk budget: \(String(format: "%.1f", maxDiskGB)) GB")
                    Slider(value: $maxDiskGB, in: 0.1...5.0, step: 0.1) {
                        Text("Disk budget")
                    }
                    Text("Oldest chunks are evicted when disk usage exceeds this limit.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Current Usage") {
                LabeledContent("Buffered") {
                    Text(ringBuffer.formattedDuration)
                }
                LabeledContent("Chunks") {
                    Text("\(ringBuffer.chunkCount) / \(ringBuffer.maxChunks)")
                }
                LabeledContent("Disk usage") {
                    Text(ringBuffer.formattedDiskUsage)
                }

                Button("Clear Buffer", role: .destructive) {
                    ringBuffer.clear()
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Processing Settings

    private var processingSettingsTab: some View {
        Form {
            Section("OCR (Vision)") {
                Toggle("Enable OCR text extraction", isOn: $ocrEngine.isEnabled)

                if ocrEngine.isEnabled {
                    LabeledContent("Frames processed") {
                        Text("\(ocrEngine.processedFrameCount)")
                    }
                    if !ocrEngine.lastRecognizedText.isEmpty {
                        LabeledContent("Last text") {
                            Text(ocrEngine.lastRecognizedText)
                                .lineLimit(2)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("Transcription (Speech)") {
                Toggle("Enable audio transcription", isOn: $transcriptionEngine.isEnabled)

                if transcriptionEngine.isEnabled {
                    LabeledContent("Chunks transcribed") {
                        Text("\(transcriptionEngine.processedChunkCount)")
                    }
                    if transcriptionEngine.isTranscribing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text("Transcribing...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    if !transcriptionEngine.lastTranscript.isEmpty {
                        LabeledContent("Last transcript") {
                            Text(transcriptionEngine.lastTranscript)
                                .lineLimit(2)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("Permissions") {
                if !TranscriptionEngine.isAuthorized {
                    Button("Request Speech Recognition Access") {
                        TranscriptionEngine.requestAuthorization { _ in }
                    }
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Speech recognition authorized")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - System Settings

    private var systemSettingsTab: some View {
        Form {
            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Section("Accessibility") {
                if MetadataCapture.hasAccessibilityPermission {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Accessibility access granted")
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading) {
                            Text("Accessibility access needed")
                            Text("Required for window title tracking.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Button("Request Accessibility Access") {
                        MetadataCapture.requestAccessibilityPermission()
                    }
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    Text("0.2.0")
                }
                LabeledContent("Architecture") {
                    Text("Backtrack DVR")
                }
            }
        }
        .formStyle(.grouped)
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
