import Foundation
import AVFoundation

#if canImport(AppKit)
import AppKit
#endif

public enum Permissions {
    public static var microphoneAuthorized: Bool {
        if #available(macOS 10.14, *) {
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
        return true
    }

    public static var microphoneDenied: Bool {
        if #available(macOS 10.14, *) {
            return AVCaptureDevice.authorizationStatus(for: .audio) == .denied
        }
        return false
    }

    public static var microphoneNotDetermined: Bool {
        if #available(macOS 10.14, *) {
            return AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
        }
        return false
    }

    public static func requestMicrophone(completion: @escaping (Bool) -> Void) {
        if #available(macOS 10.14, *) {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            switch status {
            case .authorized:
                DispatchQueue.main.async { completion(true) }
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async { completion(granted) }
                }
            case .denied, .restricted:
                DispatchQueue.main.async { completion(false) }
            @unknown default:
                DispatchQueue.main.async { completion(false) }
            }
        } else {
            DispatchQueue.main.async { completion(true) }
        }
    }

    public static func openMicrophoneSettings() {
        #if canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}
