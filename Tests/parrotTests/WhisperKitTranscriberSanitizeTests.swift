import XCTest
@testable import parrot

final class WhisperKitTranscriberSanitizeTests: XCTestCase {
    func testStripsBlankAudioToken() {
        XCTAssertEqual(WhisperKitTranscriber.sanitize("[BLANK_AUDIO]"), "")
    }

    func testStripsMixedBracketAndParenTokens() {
        let input = "[MUSIC] hello (silence) world <|endoftext|>"
        XCTAssertEqual(WhisperKitTranscriber.sanitize(input), "hello world")
    }

    func testCollapsesWhitespaceAndTrims() {
        XCTAssertEqual(WhisperKitTranscriber.sanitize("  hello   world  "), "hello world")
    }

    func testLeavesOrdinaryTextUntouched() {
        XCTAssertEqual(WhisperKitTranscriber.sanitize("turn left at the light"), "turn left at the light")
    }

    func testStripsAsteriskWrappedNoise() {
        XCTAssertEqual(WhisperKitTranscriber.sanitize("*background noise* ok go"), "ok go")
    }
}
