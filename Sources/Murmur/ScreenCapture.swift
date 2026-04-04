import Combine
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Frame rate profiles for screen capture.
enum CaptureFrameRate: Double {
    case background = 2.0    // 2 fps when buffering in background
    case reviewing  = 30.0   // 30 fps during playback / review
}

/// Captures screen frames using ScreenCaptureKit and forwards
/// CMSampleBuffers to the RingBuffer and OCR pipeline.
// Requires macOS 14+ (set in Package.swift platform target)
final class ScreenCapture: NSObject, ObservableObject {
    // MARK: - Published State

    @Published var isCapturing = false
    @Published var frameRate: CaptureFrameRate = .background
    @Published private(set) var lastFrameTime: Date?

    // MARK: - Dependencies

    private var ringBuffer: RingBuffer?
    private var ocrEngine: OCREngine?

    // MARK: - Private

    private var stream: SCStream?
    private var streamOutput: StreamOutputHandler?
    private let captureQueue = DispatchQueue(label: "com.uprootiny.murmur.screencapture", qos: .userInitiated)

    // MARK: - Configuration

    func configure(ringBuffer: RingBuffer, ocrEngine: OCREngine) {
        self.ringBuffer = ringBuffer
        self.ocrEngine = ocrEngine
    }

    // MARK: - Start / Stop

    func startCapture() async throws {
        guard !isCapturing else { return }

        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let display = content.displays.first else {
            print("[Murmur] No display found for screen capture.")
            return
        }

        // Build filter for the main display
        let filter = SCContentFilter(display: display, excludingWindows: [])

        // Build stream configuration
        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate.rawValue))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.queueDepth = 3

        // Create stream
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)

        let handler = StreamOutputHandler { [weak self] sampleBuffer in
            self?.handleFrame(sampleBuffer)
        }
        self.streamOutput = handler

        try stream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: captureQueue)
        try await stream.startCapture()

        self.stream = stream
        await MainActor.run {
            self.isCapturing = true
        }
    }

    func stopCapture() async {
        guard isCapturing, let stream = stream else { return }

        do {
            try await stream.stopCapture()
        } catch {
            print("[Murmur] Error stopping capture: \(error.localizedDescription)")
        }

        self.stream = nil
        self.streamOutput = nil
        await MainActor.run {
            self.isCapturing = false
        }
    }

    /// Update frame rate (e.g. switch between background and review mode).
    func setFrameRate(_ rate: CaptureFrameRate) async throws {
        guard let stream = stream else { return }

        let config = SCStreamConfiguration()
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(rate.rawValue))

        try await stream.updateConfiguration(config)
        await MainActor.run {
            self.frameRate = rate
        }
    }

    // MARK: - Frame Handling

    private func handleFrame(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid else { return }

        DispatchQueue.main.async {
            self.lastFrameTime = Date()
        }

        // Extract CGImage for OCR pipeline
        guard let imageBuffer = sampleBuffer.imageBuffer else { return }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        let rect = CGRect(
            x: 0, y: 0,
            width: CVPixelBufferGetWidth(imageBuffer),
            height: CVPixelBufferGetHeight(imageBuffer)
        )

        guard let cgImage = context.createCGImage(ciImage, from: rect) else { return }

        // Send to OCR engine (async, non-blocking)
        ocrEngine?.processFrame(cgImage, timestamp: Date())
    }
}

// MARK: - SCStream Output Handler

// Requires macOS 14+ (set in Package.swift platform target)
private final class StreamOutputHandler: NSObject, SCStreamOutput {
    private let onFrame: (CMSampleBuffer) -> Void

    init(onFrame: @escaping (CMSampleBuffer) -> Void) {
        self.onFrame = onFrame
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        onFrame(sampleBuffer)
    }
}
