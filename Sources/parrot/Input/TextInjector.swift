import CoreGraphics
import Foundation

/// Posts a string of text at the current cursor location by synthesizing
/// keyboard events with `CGEventKeyboardSetUnicodeString`. Works in nearly
/// every text field on macOS; some Electron apps and secure password fields
/// can drop characters (platform constraint).
enum TextInjector {
    /// Inject the given text at the current cursor location.
    /// Splits long strings into chunks because the underlying API has a
    /// per-event character limit (~20 chars).
    static func inject(_ text: String) {
        guard !text.isEmpty else { return }

        let utf16 = Array(text.utf16)
        let chunkSize = 20
        var index = 0

        while index < utf16.count {
            let end = min(index + chunkSize, utf16.count)
            var chunk = Array(utf16[index..<end])
            postChunk(&chunk)
            index = end
        }
    }

    private static func postChunk(_ chunk: inout [UniChar]) {
        let length = chunk.count
        guard length > 0 else { return }

        let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        down?.keyboardSetUnicodeString(stringLength: length, unicodeString: &chunk)
        down?.post(tap: .cgSessionEventTap)

        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        up?.keyboardSetUnicodeString(stringLength: length, unicodeString: &chunk)
        up?.post(tap: .cgSessionEventTap)
    }

    /// Replaces text this same injector previously typed — e.g. swapping a
    /// raw transcript for its cleaned-up version once that's ready. Deletes
    /// exactly `previous.count` characters backward from the cursor (one
    /// backspace per grapheme cluster, matching what a text field actually
    /// erases per keystroke) before typing the replacement, so only what we
    /// ourselves inserted is touched — never text already in the field.
    ///
    /// This is inherently "blind": if the user types or moves the cursor in
    /// the gap between the original paste and this call, the backspaces
    /// land wherever the cursor now is. There's no accessibility-API text
    /// range to target instead, since injection works by synthesizing
    /// keystrokes rather than setting a text buffer directly.
    static func replace(previous: String, with replacement: String) {
        guard previous != replacement else { return }
        deleteBackward(previous.count)
        inject(replacement)
    }

    private static func deleteBackward(_ count: Int) {
        guard count > 0 else { return }
        let deleteKeyCode: CGKeyCode = 51 // kVK_Delete
        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: nil, virtualKey: deleteKeyCode, keyDown: true)
            down?.post(tap: .cgSessionEventTap)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: deleteKeyCode, keyDown: false)
            up?.post(tap: .cgSessionEventTap)
        }
    }
}
