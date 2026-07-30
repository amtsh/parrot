import XCTest
@testable import parrot

final class ModelPreferenceTests: XCTestCase {
    private var originalValue: String?

    override func setUp() {
        super.setUp()
        originalValue = ModelPreference.selectedModelID
    }

    override func tearDown() {
        ModelPreference.selectedModelID = originalValue
        super.tearDown()
    }

    func testRoundTripsThroughUserDefaults() {
        ModelPreference.selectedModelID = "whisper-small.en"
        XCTAssertEqual(ModelPreference.selectedModelID, "whisper-small.en")
    }

    func testCanBeClearedBackToNil() {
        ModelPreference.selectedModelID = "whisper-small.en"
        ModelPreference.selectedModelID = nil
        XCTAssertNil(ModelPreference.selectedModelID)
    }
}
