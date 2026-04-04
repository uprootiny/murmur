import Foundation

// Timeline is a projection over ring buffer order; it does not mutate core state.
public final class TimelineModel {
    public private(set) var chunks: [RingBuffer.Chunk] = []
    public var selectedTime: Date = Date()

    private let ringBuffer: RingBuffer

    public init(ringBuffer: RingBuffer) {
        self.ringBuffer = ringBuffer
        reload()
    }

    public func reload() {
        chunks = ringBuffer.orderedChunks()
    }

    public var totalDuration: TimeInterval {
        Double(ringBuffer.chunkCount) * ringBuffer.chunkDurationSeconds
    }
}
