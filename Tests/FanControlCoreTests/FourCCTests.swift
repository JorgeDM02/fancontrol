import XCTest
@testable import FanControlCore

final class FourCCTests: XCTestCase {
    func testRoundTrip() {
        let key = FourCC.make("F0Ac")
        XCTAssertEqual(FourCC.string(key), "F0Ac")
    }

    func testMakeRuntime() {
        let key = FourCC.makeRuntime("Tg05")
        XCTAssertEqual(FourCC.string(key!), "Tg05")
        XCTAssertNil(FourCC.makeRuntime("F00"))
        XCTAssertNil(FourCC.makeRuntime("TOOLONG"))
    }
}