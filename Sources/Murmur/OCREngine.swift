import CoreGraphics
import Foundation
import Vision

/// Asynchronous OCR pipeline using the Vision framework.
///
/// Receives CGImage frames from ScreenCapture, runs VNRecognizeTextRequest,
/// and stores results in the SearchStore FTS5 table keyed by timestamp + chunk ID.
///
/// Design: all recognition work runs on a background queue and never blocks the
/// capture pipeline. Frames arriving while a recognition is in flight are dropped.
final class OCREngine: ObservableObject {
    // MARK: - Published State

    @Published var isEnabled: Bool = true
    @Published private(set) var lastRecognizedText: String = ""
    @Published private(set) var processedFrameCount: Int = 0

    // MARK: - Dependencies

    private var searchStore: SearchStore?
    private var ringBuffer: RingBuffer?

    // MARK: - Private

    private let recognitionQueue = DispatchQueue(label: "com.uprootiny.murmur.ocr", qos: .utility)
    private var isBusy = false
    private let minimumInterval: TimeInterval = 0.5  // Don't process more than 2 frames/sec

    private var lastProcessedTime: Date = .distantPast

    // MARK: - Configuration

    func configure(searchStore: SearchStore, ringBuffer: RingBuffer) {
        self.searchStore = searchStore
        self.ringBuffer = ringBuffer
    }

    // MARK: - Frame Processing

    /// Called by ScreenCapture with each captured frame.
    /// This method returns immediately; OCR runs asynchronously.
    func processFrame(_ image: CGImage, timestamp: Date) {
        guard isEnabled else { return }

        // Rate-limit: skip frames if we're busy or too soon after last process
        guard !isBusy else { return }
        guard timestamp.timeIntervalSince(lastProcessedTime) >= minimumInterval else { return }

        isBusy = true
        lastProcessedTime = timestamp

        recognitionQueue.async { [weak self] in
            self?.performRecognition(image: image, timestamp: timestamp)
        }
    }

    // MARK: - Vision Recognition

    private func performRecognition(image: CGImage, timestamp: Date) {
        defer {
            isBusy = false
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("[Murmur] OCR error: \(error.localizedDescription)")
            return
        }

        guard let observations = request.results else { return }

        // Collect all recognized text
        let recognizedStrings = observations.compactMap { observation -> String? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            guard candidate.confidence > 0.3 else { return nil }
            return candidate.string
        }

        guard !recognizedStrings.isEmpty else { return }

        let fullText = recognizedStrings.joined(separator: "\n")
        let chunkID = ringBuffer?.currentIndex ?? 0

        // Store in search index
        searchStore?.insertOCRText(timestamp: timestamp, chunkID: chunkID, text: fullText)

        DispatchQueue.main.async { [weak self] in
            self?.lastRecognizedText = String(fullText.prefix(200))
            self?.processedFrameCount += 1
        }
    }
}
