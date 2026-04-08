import Foundation

#if canImport(ScreenCaptureKit)
import CoreGraphics
import CoreImage
import CoreMedia
import ScreenCaptureKit

public enum CaptureFrameRate: Double {
    case background = 2.0
    case reviewing = 30.0
}

/// Captures screen frames using ScreenCaptureKit and forwards CGImages to the OCR pipeline.
@available(macOS 13.0, *)
public final class ScreenCapture: NSObject {
    public private(set) var isCapturing = false
    public var frameRate: CaptureFrameRate = .background
    public private(set) var lastFrameTime: Date?

    private var ringBuffer: RingBuffer?
    private var ocrProcessFrame: ((CGImage, Date) -> Void)?

    private var stream: SCStream?
    private var streamOutput: StreamOutputHandler?
    private let captureQueue = DispatchQueue(label: "com.murmur.screencapture", qos: .userInitiated)

    public override init() {
        super.init()
    }

    public func configure(ringBuffer: RingBuffer, ocrProcessFrame: @escaping (CGImage, Date) -> Void) {
        self.ringBuffer = ringBuffer
        self.ocrProcessFrame = ocrProcessFrame
    }

    public func startCapture() async throws {
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

    public func stopCapture() async {
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

    public func setFrameRate(_ rate: CaptureFrameRate) async throws {
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

        ocrProcessFrame?(cgImage, Date())
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
#endif
