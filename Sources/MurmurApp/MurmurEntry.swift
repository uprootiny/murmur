import AppKit
import AVFoundation
import MurmurCore

@main
struct MurmurMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var timelineWindowController: TimelineWindowController?
    private var eventMonitor: Any?

    private let ringBuffer: RingBuffer = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Murmur/Audio", isDirectory: true)
        return RingBuffer(directory: dir)
    }()

    private lazy var audioWriter = AudioChunkWriter(ringBuffer: ringBuffer)
    private let audioCapture = AudioCaptureService()
    private let exporter: ExportService = ExportService(ringBuffer: {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Murmur/Audio", isDirectory: true)
        return RingBuffer(directory: dir)
    }())

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Status item with waveform icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Murmur")
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Timeslice popover
        let timesliceView = TimeslicePopoverView(frame: NSRect(x: 0, y: 0, width: 320, height: 100))
        timesliceView.ringBuffer = ringBuffer
        timesliceView.onTimesliceSelected = { [weak self] seconds in
            self?.handleTimesliceSelected(seconds)
        }

        let viewController = NSViewController()
        viewController.view = timesliceView

        popover = NSPopover()
        popover.contentViewController = viewController
        popover.contentSize = NSSize(width: 320, height: 100)
        popover.behavior = .transient
        popover.animates = true

        audioCapture.setStateHandler { [weak self] state in
            guard let self = self else { return }
            if case .failed(let error) = state {
                self.showAlert(title: "Audio capture failed", message: error.localizedDescription)
            }
        }

        requestMicrophoneAccess()
    }

    // MARK: - Popover

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Timeline", action: #selector(openTimeline), keyEquivalent: "t"))
        menu.addItem(NSMenuItem.separator())
        let bufferInfo = String(format: "Buffer: %d chunks", ringBuffer.chunkCount)
        let infoItem = NSMenuItem(title: bufferInfo, action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Murmur", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Reset menu so left-click shows popover again
        DispatchQueue.main.async {
            self.statusItem.menu = nil
        }
    }

    // MARK: - Timeslice

    private func handleTimesliceSelected(_ seconds: TimeInterval) {
        popover.performClose(nil)

        let panel = NSOpenPanel()
        panel.message = "Choose a folder for the exported clip"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let folder = panel.url, let self = self else { return }
            let exportService = ExportService(ringBuffer: self.ringBuffer)
            exportService.exportLatest(windowSeconds: seconds, to: folder) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let url):
                        self.showAlert(title: "Exported", message: url.lastPathComponent)
                    case .failure(let error):
                        self.showAlert(title: "Export failed", message: error.localizedDescription)
                    }
                }
            }
        }
    }

    // MARK: - Timeline

    @objc private func openTimeline() {
        if timelineWindowController == nil {
            timelineWindowController = TimelineWindowController(ringBuffer: ringBuffer)
        }
        timelineWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Permissions

    private func requestMicrophoneAccess() {
        #if MURMUR_LEGACY
        audioCapture.startCapture(writer: audioWriter)
        #else
        if #available(macOS 10.14, *) {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.audioCapture.startCapture(writer: self.audioWriter)
                    } else {
                        self.showAlert(title: "Microphone access required",
                                       message: "Enable microphone access for Murmur in System Settings.")
                    }
                }
            }
        } else {
            audioCapture.startCapture(writer: audioWriter)
        }
        #endif
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
