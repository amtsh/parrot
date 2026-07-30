import Foundation

/// Live-toggleable behaviors, seeded from CLI flags at startup and flippable
/// from the menu bar without restarting the daemon. Only ever touched from
/// the main thread (menu clicks and the hotkey event callback both run there).
final class RuntimeToggles {
    var overlayEnabled: Bool
    var dumpWavEnabled: Bool
    var debugHotkeyEnabled: Bool

    init(overlayEnabled: Bool, dumpWavEnabled: Bool, debugHotkeyEnabled: Bool) {
        self.overlayEnabled = overlayEnabled
        self.dumpWavEnabled = dumpWavEnabled
        self.debugHotkeyEnabled = debugHotkeyEnabled
    }
}
