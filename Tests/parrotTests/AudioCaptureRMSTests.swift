import XCTest
@testable import parrot

final class AudioCaptureRMSTests: XCTestCase {
    func testEmptyBufferIsZero() {
        XCTAssertEqual(computeRMS([]), 0)
    }

    func testSilenceIsZero() {
        XCTAssertEqual(computeRMS([0, 0, 0, 0]), 0)
    }

    func testConstantAmplitudeMatchesItsOwnMagnitude() {
        XCTAssertEqual(computeRMS([0.5, -0.5, 0.5, -0.5]), 0.5, accuracy: 0.0001)
    }

    func testFullScaleIsOne() {
        XCTAssertEqual(computeRMS([1, -1, 1, -1]), 1.0, accuracy: 0.0001)
    }
}
