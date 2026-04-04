import Foundation

#if canImport(Combine)
import Combine
#endif

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(ScreenCaptureKit)
import CoreGraphics
import CoreMedia
import CoreImage

enum CaptureFrameRate: Double {
    case background = 2.0
    case reviewing = 30.0
}

@available(macOS 13.0, *)
final class ScreenCapture: NSObject, ObservableObject {
    @Published var isCapturing = false
    @Published var frameRate: CaptureFrameRate = .background
    @Published private(set) var lastFrameTime: Date?

    private var ringBuffer: RingBuffer?
    private var ocrEngine: OCREngine?

    private var stream: SCStream?
    private var streamOutput: StreamOutputHandler?
    private let captureQueue = DispatchQueue(label: "com.murmur.screencapture", qos: .userInitiated)

    func configure(ringBuffer: RingBuffer, ocrEngine: OCREngine) {
        self.ringBuffer = ringBuffer
        self.ocrEngine = ocrEngine
    }

    func startCapture() async throws {
        guard !isCapturing else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            MurmurLogger.shared.log("screen capture: no display found")
            return
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate.rawValue))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.queueDepth = 3

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
        MurmurLogger.shared.log("screen capture started")
    }

    func stopCapture() async {
        guard isCapturing, let stream = stream else { return }

        do {
            try await stream.stopCapture()
        } catch {
            MurmurLogger.shared.log("screen capture stop error: \(error.localizedDescription)")
        }

        self.stream = nil
        self.streamOutput = nil
        await MainActor.run {
            self.isCapturing = false
        }
        MurmurLogger.shared.log("screen capture stopped")
    }

    func setFrameRate(_ rate: CaptureFrameRate) async throws {
        guard let stream = stream else { return }

        let config = SCStreamConfiguration()
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(rate.rawValue))

        try await stream.updateConfiguration(config)
        await MainActor.run {
            self.frameRate = rate
        }
    }

    private func handleFrame(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid else { return }

        DispatchQueue.main.async {
            self.lastFrameTime = Date()
        }

        guard let imageBuffer = sampleBuffer.imageBuffer else { return }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        let rect = CGRect(
            x: 0, y: 0,
            width: CVPixelBufferGetWidth(imageBuffer),
            height: CVPixelBufferGetHeight(imageBuffer)
        )

        guard let cgImage = context.createCGImage(ciImage, from: rect) else { return }

        ocrEngine?.processFrame(cgImage, timestamp: Date())
    }
}

@available(macOS 13.0, *)
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
#else
final class ScreenCapture {
    func configure(ringBuffer: RingBuffer, ocrEngine: OCREngine) {}
    func startCapture() async throws {
        throw NSError(domain: "Murmur", code: 1, userInfo: [NSLocalizedDescriptionKey: "ScreenCaptureKit unavailable"])
    }
    func stopCapture() async {}
}
#endif
