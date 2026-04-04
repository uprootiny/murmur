import Foundation
import AVFoundation

public final class AudioCaptureService {
    public enum State {
        case idle
        case running
        case failed(Error)
    }

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "com.murmur.audio", qos: .userInitiated)
    private var isRunning = false
    private var stateHandler: ((State) -> Void)?

    public private(set) var state: State = .idle

    public init() {}

    public func setStateHandler(_ handler: @escaping (State) -> Void) {
        stateHandler = handler
    }

    public func startCapture(onBuffer: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void) {
        queue.async {
            if self.isRunning {
                return
            }
            let input = self.engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
                onBuffer(buffer, time)
            }

            do {
                self.engine.prepare()
                try self.engine.start()
                self.isRunning = true
                self.updateState(.running)
                MurmurLogger.shared.log("audio capture started")
            } catch {
                self.isRunning = false
                self.updateState(.failed(error))
                MurmurLogger.shared.log("audio capture failed: \(error.localizedDescription)")
            }
        }
    }

    public func stopCapture() {
        queue.async {
            guard self.isRunning else { return }
            self.engine.inputNode.removeTap(onBus: 0)
            self.engine.stop()
            self.isRunning = false
            self.updateState(.idle)
            MurmurLogger.shared.log("audio capture stopped")
        }
    }

    public func startCapture(writer: AudioChunkWriter) {
        startCapture { buffer, time in
            writer.append(buffer: buffer, at: time)
        }
    }

    private func updateState(_ newState: State) {
        state = newState
        if let handler = stateHandler {
            DispatchQueue.main.async {
                handler(newState)
            }
        }
    }
}
