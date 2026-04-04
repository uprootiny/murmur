import AVFoundation
import Foundation
import Speech

/// On-device audio transcription using the Speech framework.
///
/// Processes audio chunks from the RingBuffer lazily (behind the capture pipeline)
/// and stores transcripts in the SearchStore FTS5 database.
final class TranscriptionEngine: ObservableObject {
    // MARK: - Published State

    @Published var isEnabled: Bool = true
    @Published private(set) var isTranscribing: Bool = false
    @Published private(set) var lastTranscript: String = ""
    @Published private(set) var processedChunkCount: Int = 0

    // MARK: - Dependencies

    private var searchStore: SearchStore?
    private var ringBuffer: RingBuffer?

    // MARK: - Private

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let transcriptionQueue = DispatchQueue(label: "com.uprootiny.murmur.transcription", qos: .background)
    private var lastProcessedChunkIndex: Int = -1

    // MARK: - Configuration

    func configure(searchStore: SearchStore, ringBuffer: RingBuffer) {
        self.searchStore = searchStore
        self.ringBuffer = ringBuffer
    }

    // MARK: - Authorization

    /// Request speech recognition permission.
    static func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    // MARK: - Processing

    /// Process any new audio chunks that haven't been transcribed yet.
    /// Called periodically by the app (e.g. on a timer or after each chunk write).
    func processNewChunks() {
        guard isEnabled else { return }
        guard !isTranscribing else { return }
        guard let ringBuffer = ringBuffer else { return }
        guard speechRecognizer?.isAvailable == true else {
            print("[Murmur] Speech recognizer not available.")
            return
        }

        let currentIndex = ringBuffer.currentIndex
        guard currentIndex > lastProcessedChunkIndex + 1 else { return }

        // Process the next unprocessed chunk
        let nextIndex = lastProcessedChunkIndex + 1
        let slot = nextIndex % ringBuffer.maxChunks

        // Try both .m4a and .mp4 extensions
        let chunkURL: URL?
        if let url = ringBuffer.chunkURL(at: slot, extension: "m4a") {
            chunkURL = url
        } else if let url = ringBuffer.chunkURL(at: slot, extension: "mp4") {
            chunkURL = url
        } else {
            // Chunk doesn't exist (maybe evicted), skip it
            lastProcessedChunkIndex = nextIndex
            return
        }

        guard let url = chunkURL else { return }

        DispatchQueue.main.async {
            self.isTranscribing = true
        }

        transcriptionQueue.async { [weak self] in
            self?.transcribeFile(at: url, chunkIndex: nextIndex)
        }
    }

    // MARK: - Transcription

    private func transcribeFile(at url: URL, chunkIndex: Int) {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            finishChunk(chunkIndex, text: nil)
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true

        recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                print("[Murmur] Transcription error for chunk \(chunkIndex): \(error.localizedDescription)")
                self.finishChunk(chunkIndex, text: nil)
                return
            }

            guard let result = result, result.isFinal else { return }

            let transcript = result.bestTranscription.formattedString

            if !transcript.isEmpty {
                let timestamp = Date()  // approximate: time of transcription completion
                self.searchStore?.insertTranscript(
                    timestamp: timestamp,
                    chunkID: chunkIndex,
                    text: transcript
                )
            }

            self.finishChunk(chunkIndex, text: transcript)
        }
    }

    private func finishChunk(_ chunkIndex: Int, text: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastProcessedChunkIndex = chunkIndex
            self.isTranscribing = false
            self.processedChunkCount += 1
            if let text = text, !text.isEmpty {
                self.lastTranscript = String(text.prefix(200))
            }
        }
    }

    /// Reset the processed chunk counter (e.g. when the ring buffer is cleared).
    func reset() {
        lastProcessedChunkIndex = -1
        DispatchQueue.main.async {
            self.processedChunkCount = 0
            self.lastTranscript = ""
            self.isTranscribing = false
        }
    }
}
