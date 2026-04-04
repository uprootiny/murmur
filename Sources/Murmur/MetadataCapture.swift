import AppKit
import ApplicationServices
import Combine
import Foundation

/// Tracks the frontmost application and window title, storing events
/// in the SearchStore metadata table.
///
/// Uses NSWorkspace.shared.frontmostApplication observation for app changes
/// and the Accessibility API (AXUIElement) for window titles when permitted.
final class MetadataCapture: ObservableObject {
    // MARK: - Published State

    @Published var isEnabled: Bool = true
    @Published private(set) var currentAppName: String = ""
    @Published private(set) var currentWindowTitle: String = ""

    // MARK: - Dependencies

    private var searchStore: SearchStore?

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 2.0  // Check every 2 seconds

    // MARK: - Configuration

    func configure(searchStore: SearchStore) {
        self.searchStore = searchStore
    }

    // MARK: - Start / Stop

    func start() {
        observeAppChanges()
        startPolling()
    }

    func stop() {
        cancellables.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - App Change Observation

    private func observeAppChanges() {
        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .compactMap { $0 }
            .removeDuplicates { $0.processIdentifier == $1.processIdentifier }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                self?.handleAppChange(app)
            }
            .store(in: &cancellables)
    }

    private func handleAppChange(_ app: NSRunningApplication) {
        guard isEnabled else { return }

        let appName = app.localizedName ?? "Unknown"
        currentAppName = appName

        // Try to get window title via Accessibility API
        let windowTitle = Self.windowTitle(for: app.processIdentifier)
        currentWindowTitle = windowTitle ?? ""

        // Store in search index
        searchStore?.insertMetadata(
            timestamp: Date(),
            appName: appName,
            windowTitle: windowTitle,
            url: nil  // URL extraction would require per-app scripting
        )
    }

    // MARK: - Periodic Polling

    /// Polls for window title changes (the title can change without an app switch).
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

        // Only store if something changed
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

    /// Retrieves the window title for a given process using AXUIElement.
    /// Returns nil if accessibility access is not granted or no title is available.
    static func windowTitle(for pid: pid_t) -> String? {
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

    /// Check if the app has accessibility permissions.
    static var hasAccessibilityPermission: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Prompt the user to grant accessibility permissions.
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
