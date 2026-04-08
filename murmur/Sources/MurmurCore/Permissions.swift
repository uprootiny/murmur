import Foundation
import AVFoundation

#if canImport(AppKit)
import AppKit
#endif

enum Permissions {
    private static func microphoneAuthStatus() -> AVAuthorizationStatus {
        if #available(macOS 10.14, *) {
            return AVCaptureDevice.authorizationStatus(for: .audio)
        }
        return .authorized
    }

    static var microphoneAuthorized: Bool {
        microphoneAuthStatus() == .authorized
    }

    static var microphoneDenied: Bool {
        microphoneAuthStatus() == .denied
    }

    static var microphoneNotDetermined: Bool {
        microphoneAuthStatus() == .notDetermined
    }

    static func requestMicrophone(completion: @escaping (Bool) -> Void) {
        let status = microphoneAuthStatus()
        switch status {
        case .authorized:
            DispatchQueue.main.async { completion(true) }
        case .notDetermined:
            if #available(macOS 10.14, *) {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async { completion(granted) }
                }
            } else {
                DispatchQueue.main.async { completion(true) }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { completion(false) }
        @unknown default:
            DispatchQueue.main.async { completion(false) }
        }
    }

    static func openMicrophoneSettings() {
        #if canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}
