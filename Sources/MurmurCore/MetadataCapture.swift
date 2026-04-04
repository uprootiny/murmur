import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(ApplicationServices)
import ApplicationServices
#endif

#if canImport(Combine)
import Combine
#endif

#if canImport(AppKit)
final class MetadataCapture: ObservableObject {
    @Published var isEnabled: Bool = true
    @Published private(set) var currentAppName: String = ""
    @Published private(set) var currentWindowTitle: String = ""

    private var searchStore: SearchStore?
#if canImport(Combine)
    private var cancellables = Set<AnyCancellable>()
#endif
    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 2.0

    func configure(searchStore: SearchStore) {
        self.searchStore = searchStore
    }

    func start() {
        observeAppChanges()
        startPolling()
    }

    func stop() {
        cancellables.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func observeAppChanges() {
        #if canImport(Combine)
        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .compactMap { $0 }
            .removeDuplicates { $0.processIdentifier == $1.processIdentifier }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                self?.handleAppChange(app)
            }
            .store(in: &cancellables)
        #endif
    }

    private func handleAppChange(_ app: NSRunningApplication) {
        guard isEnabled else { return }

        let appName = app.localizedName ?? "Unknown"
        currentAppName = appName

        let windowTitle = Self.windowTitle(for: app.processIdentifier)
        currentWindowTitle = windowTitle ?? ""

        searchStore?.insertMetadata(
            timestamp: Date(),
            appName: appName,
            windowTitle: windowTitle,
            url: nil
        )
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

    static var hasAccessibilityPermission: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
#else
final class MetadataCapture {
    var isEnabled: Bool = false
    func configure(searchStore: SearchStore) {}
    func start() {}
    func stop() {}
}
#endif
