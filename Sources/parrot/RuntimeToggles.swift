import Foundation

/// Live-toggleable behaviors, seeded from CLI flags at startup and flippable
/// from the menu bar without restarting the daemon. Only ever touched from
/// the main thread (menu clicks and the hotkey event callback both run there).
final class RuntimeToggles {
    var overlayEnabled: Bool
    var cleanupEnabled: Bool

    init(overlayEnabled: Bool, cleanupEnabled: Bool) {
        self.overlayEnabled = overlayEnabled
        self.cleanupEnabled = cleanupEnabled
    }
}
