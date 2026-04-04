import SwiftUI

@main
struct MurmurApp: App {
    // MARK: - Core Engines

    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var screenCapture = ScreenCapture()
    @StateObject private var ocrEngine = OCREngine()
    @StateObject private var transcriptionEngine = TranscriptionEngine()
    @StateObject private var metadataCapture = MetadataCapture()
    @StateObject private var ringBuffer: RingBuffer = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let bufferDir = docs.appendingPathComponent("Murmur/Buffer", isDirectory: true)
        return RingBuffer(directory: bufferDir, maxChunks: 360, chunkDurationSeconds: 10)
    }()

    @State private var showSettings = false
    @State private var showTimeline = false

    private let searchStore = SearchStore()

    var body: some Scene {
        MenuBarExtra(
            "Murmur",
            systemImage: audioEngine.isRecording ? "waveform.circle.fill" : "waveform.circle"
        ) {
            StatusBarView(
                audioEngine: audioEngine,
                ringBuffer: ringBuffer,
                showSettings: $showSettings,
                showTimeline: $showTimeline
            )
        }

        Settings {
            SettingsView(
                audioEngine: audioEngine,
                screenCapture: screenCapture,
                ocrEngine: ocrEngine,
                transcriptionEngine: transcriptionEngine,
                ringBuffer: ringBuffer
            )
        }

        // Timeline window (opened from status bar)
        Window("Murmur Timeline", id: "timeline") {
            TimelineView(
                ringBuffer: ringBuffer,
                searchStore: SearchStoreObservable(store: searchStore)
            )
        }
        .defaultSize(width: 900, height: 600)
    }

    // MARK: - Engine Wiring

    init() {
        // Wire up dependencies between engines.
        // Note: @StateObject initializers run before body, so we configure
        // the dependency graph here. The engines hold weak/unowned refs as needed.
    }

    /// Call after StateObjects are initialized to wire cross-references.
    /// Invoked lazily on first appearance of the menu bar.
    func wireEngines() {
        ocrEngine.configure(searchStore: searchStore, ringBuffer: ringBuffer)
        transcriptionEngine.configure(searchStore: searchStore, ringBuffer: ringBuffer)
        metadataCapture.configure(searchStore: searchStore)
        screenCapture.configure(ringBuffer: ringBuffer, ocrEngine: ocrEngine)

        // Start background services
        metadataCapture.start()
    }
}
