import ApplicationServices
import AVFoundation
import Foundation

/// Side-effecting permission requests, shared between the menu bar's Setup
/// section and (independently) `parrot setup`.
enum PermissionActions {
    /// Triggers the OS accessibility prompt if not already trusted. Granting
    /// it only takes effect for a fresh process — the caller is responsible
    /// for relaunching once `AXIsProcessTrusted()` flips true.
    static func promptAccessibility() {
        guard !AXIsProcessTrusted() else { return }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    /// Requests microphone access if undetermined; opens System Settings if
    /// already denied (macOS won't re-prompt once denied).
    static func requestMicrophone(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        default:
            openMicrophoneSettings()
            completion(false)
        }
    }

    static func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    static func openKeyboardSettings() {
        open("x-apple.systempreferences:com.apple.preference.keyboard")
    }

    private static func open(_ urlString: String) {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [urlString]
        try? task.run()
    }
}
