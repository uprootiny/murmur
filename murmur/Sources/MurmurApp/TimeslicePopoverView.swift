import AppKit
import MurmurCore

/// Backtrack-style drag-to-pick timeslice popover.
/// Click and drag left to expand the capture window; release to confirm.
final class TimeslicePopoverView: NSView {
    var ringBuffer: RingBuffer?
    var onTimesliceSelected: ((TimeInterval) -> Void)?

    private var isDragging = false
    private var dragStartX: CGFloat = 0
    private var currentDragX: CGFloat = 0
    private let maxWindowSeconds: TimeInterval = 3600 // 1 hour max

    private let timeLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "drag left to select time")

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.95).cgColor
        layer?.cornerRadius = 8

        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .medium)
        timeLabel.textColor = NSColor.white
        timeLabel.alignment = .center
        timeLabel.stringValue = "0:00"
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)

        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = NSColor(white: 0.5, alpha: 1)
        hintLabel.alignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)

        NSLayoutConstraint.activate([
            timeLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -8),
            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 4),
        ])
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds
        let barHeight: CGFloat = 4
        let barY = bounds.height - 16

        // Background bar (full buffer duration)
        let bgBar = NSRect(x: 8, y: barY, width: bounds.width - 16, height: barHeight)
        NSColor(white: 0.25, alpha: 1).setFill()
        NSBezierPath(roundedRect: bgBar, xRadius: 2, yRadius: 2).fill()

        if isDragging {
            // Selected region (from drag start to current position)
            let left = min(dragStartX, currentDragX)
            let right = max(dragStartX, currentDragX)
            let selRect = NSRect(x: left, y: barY - 2, width: right - left, height: barHeight + 4)
            NSColor(calibratedRed: 0.3, green: 0.6, blue: 1.0, alpha: 0.8).setFill()
            NSBezierPath(roundedRect: selRect, xRadius: 2, yRadius: 2).fill()
        }

        // Chunk tick marks
        let chunkCount = ringBuffer?.chunkCount ?? 0
        let maxChunks = ringBuffer?.maxChunks ?? 360
        if chunkCount > 0 && maxChunks > 0 {
            let usableWidth = bounds.width - 16
            let tickSpacing = usableWidth / CGFloat(maxChunks)
            NSColor(white: 0.4, alpha: 1).setFill()
            for i in 0..<chunkCount {
                let x = 8 + CGFloat(i) * tickSpacing
                let tick = NSRect(x: x, y: barY - 1, width: 1, height: barHeight + 2)
                tick.fill()
            }
        }
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        isDragging = true
        dragStartX = point.x
        currentDragX = point.x
        hintLabel.stringValue = "release to capture"
        updateTimeLabel()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        currentDragX = point.x
        updateTimeLabel()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false

        let seconds = secondsFromDrag()
        if seconds > 0 {
            onTimesliceSelected?(seconds)
        }

        hintLabel.stringValue = "drag left to select time"
        timeLabel.stringValue = "0:00"
        needsDisplay = true
    }

    // MARK: - Helpers

    private func secondsFromDrag() -> TimeInterval {
        let pixelDelta = abs(dragStartX - currentDragX)
        let usableWidth = bounds.width - 16
        guard usableWidth > 0 else { return 0 }

        let bufferDuration: TimeInterval
        if let rb = ringBuffer {
            bufferDuration = Double(rb.chunkCount) * rb.chunkDurationSeconds
        } else {
            bufferDuration = maxWindowSeconds
        }

        let fraction = Double(pixelDelta) / Double(usableWidth)
        return min(fraction * bufferDuration, bufferDuration)
    }

    private func updateTimeLabel() {
        let seconds = Int(secondsFromDrag())
        let mins = seconds / 60
        let secs = seconds % 60
        timeLabel.stringValue = String(format: "%d:%02d", mins, secs)
    }
}
