import XCTest
@testable import parrot

final class CleanupPreferenceTests: XCTestCase {
    private var originalValue: Bool?

    override func setUp() {
        super.setUp()
        originalValue = UserDefaults.standard.object(forKey: "parrot.cleanupEnabled") as? Bool
    }

    override func tearDown() {
        if let originalValue {
            CleanupPreference.enabled = originalValue
        } else {
            UserDefaults.standard.removeObject(forKey: "parrot.cleanupEnabled")
        }
        super.tearDown()
    }

    func testDefaultsToEnabledWhenNeverSet() {
        UserDefaults.standard.removeObject(forKey: "parrot.cleanupEnabled")
        XCTAssertTrue(CleanupPreference.enabled)
    }

    func testCanBeDisabledAndReadBack() {
        CleanupPreference.enabled = false
        XCTAssertFalse(CleanupPreference.enabled)
    }

    func testCanBeReenabledAfterDisabling() {
        CleanupPreference.enabled = false
        CleanupPreference.enabled = true
        XCTAssertTrue(CleanupPreference.enabled)
    }
}
