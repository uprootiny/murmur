import AVFoundation
import Combine
import Foundation

enum AudioQuality: String, CaseIterable, Identifiable {
    case high = "High (48 kHz)"
    case low = "Low (22 kHz)"

    var id: String { rawValue }

    var sampleRate: Double {
        switch self {
        case .high: return 48_000
        case .low: return 22_050
        }
    }
}

final class AudioEngine: ObservableObject {
    // MARK: - Published State

    @Published var isRecording = false
    @Published var isPaused = false
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var currentDeviceName: String = "Default"
    @Published var availableDevices: [AVCaptureDevice] = []
    @Published var quality: AudioQuality = .high
    @Published var maxSegmentMinutes: Int = 30
    @Published var storageURL: URL

    // MARK: - Private

    private var engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var segmentStart = Date()
    private var timer: Timer?
    private var segmentIndex = 0
    private var sessionTimestamp = ""
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.storageURL = docs.appendingPathComponent("Murmur", isDirectory: true)
        createStorageDirectoryIfNeeded()
        refreshDevices()
        observeDeviceChanges()
    }

    // MARK: - Directory

    private func createStorageDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
    }

    // MARK: - Device Enumeration

    func refreshDevices() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        availableDevices = discoverySession.devices
        if let first = availableDevices.first {
            currentDeviceName = first.localizedName
        }
    }

    private func observeDeviceChanges() {
        NotificationCenter.default.publisher(for: .AVCaptureDeviceWasConnected)
            .merge(with: NotificationCenter.default.publisher(for: .AVCaptureDeviceWasDisconnected))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshDevices()
                if self?.isRecording == true {
                    self?.handleDeviceChange()
                }
            }
            .store(in: &cancellables)
    }

    private func handleDeviceChange() {
        // Restart the engine to pick up device changes
        let wasRecording = isRecording
        stopEngine()
        if wasRecording {
            startEngine()
        }
    }

    // MARK: - Recording Control

    func start() {
        guard !isRecording else { return }
        guard Permissions.microphoneAuthorized else {
            Permissions.requestMicrophone { [weak self] granted in
                if granted {
                    DispatchQueue.main.async { self?.start() }
                }
            }
            return
        }
        sessionTimestamp = Self.timestampString()
        segmentIndex = 0
        elapsedSeconds = 0
        startEngine()
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        engine.pause()
        isPaused = true
        timer?.invalidate()
    }

    func resume() {
        guard isRecording, isPaused else { return }
        try? engine.start()
        isPaused = false
        startTimer()
    }

    func stop() {
        stopEngine()
        elapsedSeconds = 0
    }

    // MARK: - Engine Lifecycle

    private func startEngine() {
        engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            print("[Murmur] No valid audio input format available.")
            return
        }

        // Create output file
        audioFile = createAudioFile(sampleRate: inputFormat.sampleRate, channels: inputFormat.channelCount)
        guard audioFile != nil else {
            print("[Murmur] Failed to create audio file.")
            return
        }

        segmentStart = Date()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }

        do {
            try engine.start()
            isRecording = true
            isPaused = false
            startTimer()
        } catch {
            print("[Murmur] Engine start failed: \(error.localizedDescription)")
        }
    }

    private func stopEngine() {
        timer?.invalidate()
        timer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        isRecording = false
        isPaused = false
    }

    // MARK: - Buffer Handling

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let file = audioFile else { return }

        // Check segment duration
        let elapsed = Date().timeIntervalSince(segmentStart)
        if elapsed >= Double(maxSegmentMinutes) * 60.0 {
            rotateSegment()
            return
        }

        do {
            try file.write(from: buffer)
        } catch {
            print("[Murmur] Write error: \(error.localizedDescription)")
        }
    }

    private func rotateSegment() {
        // Close current file
        audioFile = nil
        segmentIndex += 1

        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        audioFile = createAudioFile(sampleRate: inputFormat.sampleRate, channels: inputFormat.channelCount)
        segmentStart = Date()
    }

    // MARK: - File Creation

    private func createAudioFile(sampleRate: Double, channels: AVAudioChannelCount) -> AVAudioFile? {
        createStorageDirectoryIfNeeded()

        let segmentSuffix = segmentIndex > 0 ? "_part\(segmentIndex)" : ""
        let filename = "murmur_\(sessionTimestamp)\(segmentSuffix).m4a"
        let fileURL = storageURL.appendingPathComponent(filename)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: quality.sampleRate,
            AVNumberOfChannelsKey: Int(channels),
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let file = try AVAudioFile(forWriting: fileURL, settings: settings)
            return file
        } catch {
            print("[Murmur] File creation error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.elapsedSeconds += 1
            }
        }
    }

    // MARK: - Helpers

    static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }

    var formattedDuration: String {
        let hours = Int(elapsedSeconds) / 3600
        let minutes = (Int(elapsedSeconds) % 3600) / 60
        let seconds = Int(elapsedSeconds) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func openRecordingsFolder() {
        NSWorkspace.shared.open(storageURL)
    }
}
