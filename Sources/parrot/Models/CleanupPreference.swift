import Foundation

/// Persists the "Auto Text Cleanup" menu toggle across launches. Defaults to
/// on — absence of a stored value means enabled, not disabled.
enum CleanupPreference {
    private static let key = "parrot.cleanupEnabled"

    static var enabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
