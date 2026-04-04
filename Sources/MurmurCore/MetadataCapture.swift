import Foundation

#if canImport(AppKit)
import AppKit
import ApplicationServices

/// Tracks the frontmost application and window title, storing events
/// in the SearchStore metadata table.
public final class MetadataCapture {
    public var isEnabled: Bool = true
    public private(set) var currentAppName: String = ""
    public private(set) var currentWindowTitle: String = ""

    private var searchStore: SearchStore?
    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 2.0

    public init() {}

    public func configure(searchStore: SearchStore) {
        self.searchStore = searchStore
    }

    public func start() {
        startPolling()
    }

    public func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollCurrentWindow()
        }
    }

    private func pollCurrentWindow() {
        guard isEnabled else { return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }

        let appName = app.localizedName ?? "Unknown"
        let windowTitle = Self.windowTitle(for: app.processIdentifier)

        let titleChanged = (windowTitle ?? "") != currentWindowTitle
        let appChanged = appName != currentAppName

        if titleChanged || appChanged {
            currentAppName = appName
            currentWindowTitle = windowTitle ?? ""

            searchStore?.insertMetadata(
                timestamp: Date(),
                appName: appName,
                windowTitle: windowTitle,
                url: nil
            )
        }
    }

    // MARK: - Accessibility API

    public static func windowTitle(for pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)

        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard result == .success else { return nil }

        var title: AnyObject?
        let titleResult = AXUIElementCopyAttributeValue(
            focusedWindow as! AXUIElement,
            kAXTitleAttribute as CFString,
            &title
        )
        guard titleResult == .success else { return nil }

        return title as? String
    }

    public static var hasAccessibilityPermission: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
#else
public final class MetadataCapture {
    public var isEnabled: Bool = false
    public init() {}
    public func configure(searchStore: SearchStore) {}
    public func start() {}
    public func stop() {}
}
#endif
