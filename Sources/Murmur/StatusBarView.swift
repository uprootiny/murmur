import AVFoundation
import SwiftUI

struct StatusBarView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var ringBuffer: RingBuffer
    @Binding var showSettings: Bool
    @Binding var showTimeline: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status header
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.headline)
                Spacer()
                Text(audioEngine.formattedDuration)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)

            // Buffer duration display
            HStack(spacing: 6) {
                Image(systemName: "circle.dotted.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(ringBuffer.formattedDuration) buffered")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                // Disk usage indicator
                Image(systemName: diskUsageIcon)
                    .font(.caption)
                    .foregroundColor(diskUsageColor)
                Text(ringBuffer.formattedDiskUsage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)

            Divider()

            // Transport controls
            HStack(spacing: 12) {
                if !audioEngine.isRecording {
                    Button(action: { audioEngine.start() }) {
                        Label("Record", systemImage: "record.circle")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                } else if audioEngine.isPaused {
                    Button(action: { audioEngine.resume() }) {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                } else {
                    Button(action: { audioEngine.pause() }) {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .keyboardShortcut("p", modifiers: .command)
                }

                if audioEngine.isRecording {
                    Button(action: { audioEngine.stop() }) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .keyboardShortcut("s", modifiers: .command)
                }
            }
            .padding(.horizontal, 4)

            Divider()

            // Search / Timeline button
            Button(action: {
                openWindow(id: "timeline")
            }) {
                Label("Search Timeline...", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: .command)
            .padding(.horizontal, 4)

            Divider()

            // Input device picker
            if !audioEngine.availableDevices.isEmpty {
                Menu {
                    ForEach(audioEngine.availableDevices, id: \.uniqueID) { device in
                        Button(device.localizedName) {
                            audioEngine.currentDeviceName = device.localizedName
                        }
                    }
                } label: {
                    Label(audioEngine.currentDeviceName, systemImage: "mic")
                }
                .padding(.horizontal, 4)
            }

            Divider()

            // Utility actions
            Button(action: { audioEngine.openRecordingsFolder() }) {
                Label("Open Recordings Folder", systemImage: "folder")
            }
            .padding(.horizontal, 4)

            Button(action: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }) {
                Label("Settings...", systemImage: "gear")
            }
            .keyboardShortcut(",", modifiers: .command)
            .padding(.horizontal, 4)

            Divider()

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit Murmur", systemImage: "xmark.circle")
            }
            .keyboardShortcut("q", modifiers: .command)
            .padding(.horizontal, 4)
        }
        .padding(8)
        .frame(width: 280)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        if audioEngine.isRecording && !audioEngine.isPaused {
            return .red
        } else if audioEngine.isPaused {
            return .yellow
        }
        return .gray
    }

    private var statusText: String {
        if audioEngine.isRecording && !audioEngine.isPaused {
            return "Recording"
        } else if audioEngine.isPaused {
            return "Paused"
        }
        return "Idle"
    }

    /// Icon indicating disk usage level.
    private var diskUsageIcon: String {
        let usage = ringBuffer.diskUsage
        let budget = ringBuffer.maxDiskBytes
        let ratio = Double(usage) / Double(budget)
        if ratio > 0.9 { return "externaldrive.fill.badge.exclamationmark" }
        if ratio > 0.7 { return "externaldrive.fill.badge.minus" }
        return "externaldrive"
    }

    /// Color indicating disk usage severity.
    private var diskUsageColor: Color {
        let usage = ringBuffer.diskUsage
        let budget = ringBuffer.maxDiskBytes
        let ratio = Double(usage) / Double(budget)
        if ratio > 0.9 { return .red }
        if ratio > 0.7 { return .orange }
        return .secondary
    }
}
