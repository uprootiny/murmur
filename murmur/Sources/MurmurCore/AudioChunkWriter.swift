import Foundation
import AVFoundation

public final class AudioChunkWriter {
    private let ringBuffer: RingBuffer
    private let queue = DispatchQueue(label: "com.murmur.audiowriter", qos: .utility)

    private var currentFile: AVAudioFile?
    private var framesWritten: AVAudioFramePosition = 0
    private var currentStart: Date?
    public private(set) var lastError: Error?

    public init(ringBuffer: RingBuffer) {
        self.ringBuffer = ringBuffer
    }

    public func append(buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        queue.async {
            self.ensureFile(format: buffer.format)
            guard self.currentFile != nil else {
                return
            }
            do {
                try self.currentFile?.write(from: buffer)
                self.framesWritten += AVAudioFramePosition(buffer.frameLength)
                let duration = Double(self.framesWritten) / buffer.format.sampleRate
                let wallDuration = Date().timeIntervalSince(self.currentStart ?? Date())
                if duration >= self.ringBuffer.chunkDuration || wallDuration >= self.ringBuffer.chunkDuration {
                    self.rotateFile()
                }
            } catch {
                // Drop on error to avoid blocking capture.
                self.lastError = error
                MurmurLogger.shared.log("chunk write error: \\(error.localizedDescription)")
                self.rotateFile()
            }
        }
    }

    public func stop() {
        queue.async {
            self.currentFile = nil
            self.framesWritten = 0
            self.currentStart = nil
        }
    }

    private func ensureFile(format: AVAudioFormat) {
        if currentFile != nil { return }
        let url = ringBuffer.nextChunkURL(fileExtension: "m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 128_000
        ]

        do {
            currentFile = try AVAudioFile(forWriting: url, settings: settings)
            framesWritten = 0
            currentStart = Date()
            MurmurLogger.shared.log("new chunk: \\(url.lastPathComponent)")
        } catch {
            lastError = error
            MurmurLogger.shared.log("chunk open error: \\(error.localizedDescription)")
            currentFile = nil
        }
    }

    private func rotateFile() {
        let hadData = currentFile != nil && framesWritten > 0
        currentFile = nil
        framesWritten = 0
        currentStart = nil
        if hadData {
            MurmurLogger.shared.log("chunk rotate")
            ringBuffer.advanceIndex()
        }
    }
}
