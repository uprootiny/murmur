import CoreGraphics
import Foundation

#if canImport(Vision)
import Vision

/// Asynchronous OCR pipeline using the Vision framework.
/// All recognition runs on a background queue and never blocks the capture pipeline.
@available(macOS 10.15, *)
public final class OCREngine {
    public var isEnabled: Bool = true
    public private(set) var lastRecognizedText: String = ""
    public private(set) var processedFrameCount: Int = 0

    private var searchStore: SearchStore?
    private var ringBuffer: RingBuffer?

    private let recognitionQueue = DispatchQueue(label: "com.murmur.ocr", qos: .utility)
    private var isBusy = false
    private let minimumInterval: TimeInterval = 0.5
    private var lastProcessedTime: Date = .distantPast

    public init() {}

    public func configure(searchStore: SearchStore, ringBuffer: RingBuffer) {
        self.searchStore = searchStore
        self.ringBuffer = ringBuffer
    }

    public func processFrame(_ image: CGImage, timestamp: Date) {
        guard isEnabled else { return }
        guard !isBusy else { return }
        guard timestamp.timeIntervalSince(lastProcessedTime) >= minimumInterval else { return }

        isBusy = true
        lastProcessedTime = timestamp

        recognitionQueue.async { [weak self] in
            self?.performRecognition(image: image, timestamp: timestamp)
        }
    }

    private func performRecognition(image: CGImage, timestamp: Date) {
        defer { isBusy = false }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            MurmurLogger.shared.log("OCR error: \(error.localizedDescription)")
            return
        }

        guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

        let recognizedStrings = observations.compactMap { observation -> String? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            guard candidate.confidence > 0.3 else { return nil }
            return candidate.string
        }

        guard !recognizedStrings.isEmpty else { return }

        let fullText = recognizedStrings.joined(separator: "\n")
        let chunkID = ringBuffer?.currentIndex ?? 0

        searchStore?.insertOCRText(timestamp: timestamp, chunkID: chunkID, text: fullText)

        DispatchQueue.main.async { [weak self] in
            self?.lastRecognizedText = String(fullText.prefix(200))
            self?.processedFrameCount += 1
        }
    }
}
#endif
