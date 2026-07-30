import XCTest
@testable import parrot

final class ModelRegistryTests: XCTestCase {
    func testFindReturnsKnownModel() {
        let model = ModelRegistry.find("whisper-base.en")
        XCTAssertEqual(model?.id, "whisper-base.en")
    }

    func testFindReturnsNilForUnknownID() {
        XCTAssertNil(ModelRegistry.find("does-not-exist"))
    }

    func testRecommendedIsMarkedRecommended() {
        let recommended = ModelRegistry.recommended()
        XCTAssertNotNil(recommended)
        XCTAssertTrue(recommended?.recommended ?? false)
    }

    func testExactlyOneModelIsRecommended() {
        let recommendedCount = ModelRegistry.shared.filter(\.recommended).count
        XCTAssertEqual(recommendedCount, 1)
    }

    func testAllModelIDsAreUnique() {
        let ids = ModelRegistry.shared.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }
}
