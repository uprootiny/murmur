import AppKit
import MurmurCore

final class TimelineWindowController: NSWindowController {
    convenience init(ringBuffer: RingBuffer) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Murmur Timeline"
        window.contentViewController = TimelineViewController(ringBuffer: ringBuffer)
        self.init(window: window)
    }
}

final class TimelineViewController: NSViewController {
    private let model: TimelineModel
    private let exporter: ExportService
    private var refreshTimer: Timer?

    private let titleLabel = NSTextField(labelWithString: "Rolling Audio Timeline")
    private let durationLabel = NSTextField(labelWithString: "Buffer: 0 sec")
    private let positionLabel = NSTextField(labelWithString: "Position: 0 sec")
    private let barView = TimelineBarView()
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 60, target: nil, action: nil)
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save Clip", target: nil, action: nil)
    private let playButton = NSButton(title: "Play", target: nil, action: nil)

    private var isPlaying = false
    private var playbackTimer: Timer?

    init(ringBuffer: RingBuffer) {
        self.model = TimelineModel(ringBuffer: ringBuffer)
        self.exporter = ExportService(ringBuffer: ringBuffer)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        durationLabel.textColor = .secondaryLabelColor
        positionLabel.textColor = .secondaryLabelColor

        slider.target = self
        slider.action = #selector(sliderChanged)
        refreshButton.target = self
        refreshButton.action = #selector(refresh)
        saveButton.target = self
        saveButton.action = #selector(saveClip)
        playButton.target = self
        playButton.action = #selector(togglePlay)

        let header = NSStackView(views: [titleLabel, playButton, refreshButton, saveButton])
        header.orientation = NSUserInterfaceLayoutOrientation.horizontal
        header.distribution = .gravityAreas
        header.alignment = .centerY
        header.spacing = 12

        let labels = NSStackView(views: [durationLabel, positionLabel])
        labels.orientation = NSUserInterfaceLayoutOrientation.horizontal
        labels.distribution = .fillEqually

        let layout = NSStackView(views: [header, barView, slider, labels])
        layout.orientation = NSUserInterfaceLayoutOrientation.vertical
        layout.spacing = 16
        layout.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)

        layout.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(layout)

        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            layout.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            layout.topAnchor.constraint(equalTo: view.topAnchor),
            layout.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        refresh()
        refreshTimer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        refreshTimer?.invalidate()
        playbackTimer?.invalidate()
    }

    @objc private func refresh() {
        model.reload()
        let total = max(model.totalDuration, 1)
        slider.maxValue = total
        durationLabel.stringValue = "Buffer: \(formatSeconds(total))"
        barView.duration = total
        updatePositionLabel()
    }

    @objc private func sliderChanged() {
        updatePositionLabel()
    }

    private func updatePositionLabel() {
        positionLabel.stringValue = "Position: \(formatSeconds(slider.doubleValue))"
        barView.position = slider.doubleValue
    }

    @objc private func saveClip() {
        let panel = NSOpenPanel()
        panel.message = "Choose a folder for the export"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let folder = panel.url, let self else { return }
            let windowSeconds = max(self.slider.doubleValue, 1)
            self.exporter.exportLatest(windowSeconds: windowSeconds, to: folder) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let url):
                        self.showExportResult(message: "Exported to \(url.lastPathComponent)")
                    case .failure:
                        self.showExportResult(message: "Export failed")
                    }
                }
            }
        }
    }

    @objc private func togglePlay() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        isPlaying = true
        playButton.title = "Pause"
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(stepPlayback), userInfo: nil, repeats: true)
    }

    private func stopPlayback() {
        isPlaying = false
        playButton.title = "Play"
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    @objc private func stepPlayback() {
        let maxValue = slider.maxValue
        if slider.doubleValue >= maxValue {
            stopPlayback()
            return
        }
        slider.doubleValue = min(slider.doubleValue + 0.1, maxValue)
        updatePositionLabel()
    }

    private func showExportResult(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func formatSeconds(_ seconds: Double) -> String {
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        if mins > 0 {
            return String(format: "%dm %02ds", mins, secs)
        }
        return "\(secs)s"
    }
}

final class TimelineBarView: NSView {
    var duration: Double = 60 { didSet { needsDisplay = true } }
    var position: Double = 0 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds.insetBy(dx: 6, dy: 6)
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        bgPath.fill()

        let tickCount = max(Int(bounds.width / 60), 4)
        let tickSpacing = bounds.width / CGFloat(tickCount)
        let tickHeight: CGFloat = 8

        NSColor.secondaryLabelColor.setStroke()
        for i in 0...tickCount {
            let x = bounds.minX + CGFloat(i) * tickSpacing
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x, y: bounds.minY + 6))
            path.line(to: NSPoint(x: x, y: bounds.minY + 6 + tickHeight))
            path.lineWidth = 1
            path.stroke()
        }

        let normalized = duration > 0 ? min(max(position / duration, 0), 1) : 0
        let playheadX = bounds.minX + bounds.width * CGFloat(normalized)
        let playhead = NSBezierPath()
        playhead.move(to: NSPoint(x: playheadX, y: bounds.minY))
        playhead.line(to: NSPoint(x: playheadX, y: bounds.maxY))
        NSColor.systemBlue.setStroke()
        playhead.lineWidth = 2
        playhead.stroke()
    }
}
