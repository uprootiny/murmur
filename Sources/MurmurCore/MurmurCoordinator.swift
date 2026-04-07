import Foundation

#if canImport(Speech)
import Speech
#endif

/// Wires the intelligence engines to the capture pipeline.
/// Polls the ring buffer for new chunks and triggers transcription
/// and metadata capture on each advance.
@available(macOS 10.15, *)
public final class MurmurCoordinator {
    private let ringBuffer: RingBuffer
    private let searchStore: SearchStore
    private let metadataCapture: MetadataCapture

    #if canImport(Speech)
    private let transcriptionEngine: TranscriptionEngine
    #endif

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 2.0
    private var lastSeenIndex: Int = -1

    public init(ringBuffer: RingBuffer) {
        self.ringBuffer = ringBuffer
        self.searchStore = SearchStore()
        self.metadataCapture = MetadataCapture()

        #if canImport(Speech)
        self.transcriptionEngine = TranscriptionEngine()
        #endif

        configure()
    }

    private func configure() {
        metadataCapture.configure(searchStore: searchStore)

        #if canImport(Speech)
        transcriptionEngine.configure(searchStore: searchStore, ringBuffer: ringBuffer)
        #endif

        lastSeenIndex = ringBuffer.currentIndex
    }

    public func start() {
        metadataCapture.start()

        #if canImport(Speech)
        TranscriptionEngine.requestAuthorization { granted in
            if granted {
                MurmurLogger.shared.log("speech recognition authorized")
            } else {
                MurmurLogger.shared.log("speech recognition not authorized", level: .warning)
            }
        }
        #endif

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }

        MurmurLogger.shared.log("coordinator started")
    }

    public func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        metadataCapture.stop()
        MurmurLogger.shared.log("coordinator stopped")
    }

    private func poll() {
        let currentIndex = ringBuffer.currentIndex
        guard currentIndex > lastSeenIndex else { return }
        lastSeenIndex = currentIndex

        #if canImport(Speech)
        transcriptionEngine.processNewChunks()
        #endif
    }

    public func search(query: String) -> [SearchResult] {
        searchStore.search(query: query)
    }
}
