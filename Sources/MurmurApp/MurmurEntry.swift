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
    private var timelineWindowController: TimelineWindowController?

    private let ringBuffer: RingBuffer = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Murmur/Audio", isDirectory: true)
        return RingBuffer(directory: dir)
    }()

    private lazy var audioWriter = AudioChunkWriter(ringBuffer: ringBuffer)
    private let audioCapture = AudioCaptureService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.title = "Mm"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Timeline", action: #selector(openTimeline), keyEquivalent: "t"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Murmur", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        audioCapture.setStateHandler { [weak self] state in
            guard let self else { return }
            if case .failed(let error) = state {
                self.showCaptureFailedAlert(error: error)
            }
        }

        requestMicrophoneAccess()
    }

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
                        self.showMicDeniedAlert()
                    }
                }
            }
        } else {
            // Legacy builds start capture without runtime permission prompt.
            audioCapture.startCapture(writer: audioWriter)
        }
        #endif
    }

    private func showMicDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Microphone access is required"
        alert.informativeText = "Enable microphone access for Murmur in System Settings."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showCaptureFailedAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Audio capture failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
