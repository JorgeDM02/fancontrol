import XCTest
import FanControlCore

final class CurveEvaluatorTests: XCTestCase {

    func testBelowFirstPointReturnsAutoUnlessHysteresisHeld() {
        let curve = FanCurve(
            name: "t",
            fanIndex: 0,
            sensorKey: "TCDX",
            points: [
                CurvePoint(temperatureC: 40, rpm: 2000),
                CurvePoint(temperatureC: 80, rpm: 6000),
            ]
        )
        // Cold, never active → nil (auto).
        XCTAssertNil(CurveEvaluator.evaluate(curve: curve, temperature: 30,
                                              minRPM: 1000, maxRPM: 7000, currentlyActive: false))
        // Cold but previously engaged, within deadband → hold first-point RPM.
        XCTAssertEqual(CurveEvaluator.evaluate(curve: curve, temperature: 38,
                                               minRPM: 1000, maxRPM: 7000, currentlyActive: true), 2000)
        // Dropped past deadband → release.
        XCTAssertNil(CurveEvaluator.evaluate(curve: curve, temperature: 30,
                                             minRPM: 1000, maxRPM: 7000, currentlyActive: true))
    }

    func testLinearInterpolation() {
        let curve = FanCurve(
            name: "t",
            fanIndex: 0,
            sensorKey: "TCDX",
            points: [
                CurvePoint(temperatureC: 40, rpm: 2000),
                CurvePoint(temperatureC: 60, rpm: 4000),
            ]
        )
        // Midpoint 50°C → 3000 RPM.
        XCTAssertEqual(CurveEvaluator.evaluate(curve: curve, temperature: 50,
                                               minRPM: 0, maxRPM: 8000, currentlyActive: false), 3000)
    }

    func testMultiFanAndLegacyDecode() {
        // Legacy saved format used a single `fanIndex`; must still load.
        let legacy = #"""
        [{"id":"00000000-0000-0000-0000-000000000001","name":"old",
          "fanIndex":1,"sensorKey":"TCDX","points":[],"isEnabled":true}]
        """#.data(using: .utf8)!
        let decoded = try! JSONDecoder().decode([FanCurve].self, from: legacy)
        XCTAssertEqual(decoded[0].fanIndices, [1])

        // New format stores an array and may target multiple fans.
        let multi = FanCurve(name: "both", fanIndices: [1, 0], sensorKey: "TCDX")
        XCTAssertEqual(multi.fanIndices, [0, 1])
        XCTAssertTrue(multi.targets(0) && multi.targets(1) && !multi.targets(2))

        // Codable round-trips the array.
        let data = try! JSONEncoder().encode(multi)
        let roundtrip = try! JSONDecoder().decode(FanCurve.self, from: data)
        XCTAssertEqual(roundtrip.fanIndices, [0, 1])
    }

    func testClamping() {
        let curve = FanCurve(
            name: "t",
            fanIndex: 0,
            sensorKey: "TCDX",
            points: [
                CurvePoint(temperatureC: 40, rpm: 2000),
                CurvePoint(temperatureC: 80, rpm: 6000),
            ]
        )
        // 100°C → last point (6000), clamped by fan max of 5000.
        XCTAssertEqual(CurveEvaluator.evaluate(curve: curve, temperature: 100,
                                               minRPM: 1000, maxRPM: 5000, currentlyActive: false), 5000)
        // Above-last point with generous max → last point RPM.
        XCTAssertEqual(CurveEvaluator.evaluate(curve: curve, temperature: 100,
                                               minRPM: 1000, maxRPM: 8000, currentlyActive: false), 6000)
        // No points → nil.
        let empty = FanCurve(name: "e", fanIndex: 0, sensorKey: "TCDX", points: [])
        XCTAssertNil(CurveEvaluator.evaluate(curve: empty, temperature: 50,
                                             minRPM: 1000, maxRPM: 5000, currentlyActive: false))
    }
}