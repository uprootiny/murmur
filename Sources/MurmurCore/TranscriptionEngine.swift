import AVFoundation
import Foundation

#if canImport(Combine)
import Combine
#endif

#if canImport(Speech)
import Speech
#endif

#if canImport(Speech)
final class TranscriptionEngine: ObservableObject {
    @Published var isEnabled: Bool = true
    @Published private(set) var isTranscribing: Bool = false
    @Published private(set) var lastTranscript: String = ""
    @Published private(set) var processedChunkCount: Int = 0

    private var searchStore: SearchStore?
    private var ringBuffer: RingBuffer?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let transcriptionQueue = DispatchQueue(label: "com.murmur.transcription", qos: .background)
    private var lastProcessedChunkIndex: Int = -1

    func configure(searchStore: SearchStore, ringBuffer: RingBuffer) {
        self.searchStore = searchStore
        self.ringBuffer = ringBuffer
    }

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

    func processNewChunks() {
        guard isEnabled else { return }
        guard !isTranscribing else { return }
        guard let ringBuffer = ringBuffer else { return }
        guard speechRecognizer?.isAvailable == true else {
            MurmurLogger.shared.log("speech recognizer not available")
            return
        }

        let currentIndex = ringBuffer.currentIndex
        guard currentIndex > lastProcessedChunkIndex + 1 else { return }

        let nextIndex = lastProcessedChunkIndex + 1
        let slot = nextIndex % ringBuffer.maxChunks

        let chunkURL: URL?
        if let url = ringBuffer.chunkURL(at: slot, extension: "m4a") {
            chunkURL = url
        } else if let url = ringBuffer.chunkURL(at: slot, extension: "mp4") {
            chunkURL = url
        } else {
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
                MurmurLogger.shared.log("transcription error: \(error.localizedDescription)")
                self.finishChunk(chunkIndex, text: nil)
                return
            }

            guard let result = result, result.isFinal else { return }

            let transcript = result.bestTranscription.formattedString

            if !transcript.isEmpty {
                let timestamp = Date()
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

    func reset() {
        lastProcessedChunkIndex = -1
        DispatchQueue.main.async {
            self.processedChunkCount = 0
            self.lastTranscript = ""
            self.isTranscribing = false
        }
    }
}
#else
final class TranscriptionEngine {
    var isEnabled: Bool = false
    func configure(searchStore: SearchStore, ringBuffer: RingBuffer) {}
    static func requestAuthorization(completion: @escaping (Bool) -> Void) { completion(false) }
    static var isAuthorized: Bool { false }
    func processNewChunks() {}
    func reset() {}
}
#endif
