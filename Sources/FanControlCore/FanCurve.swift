import Foundation

/// A single control point on a fan curve: temperature -> RPM.
public struct CurvePoint: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var temperatureC: Double
    public var rpm: Double

    public init(id: UUID = UUID(),
                temperatureC: Double,
                rpm: Double) {
        self.id = id
        self.temperatureC = temperatureC
        self.rpm = rpm
    }
}

/// A temperature-driven fan curve. Maps a single sensor's temperature to
/// a target RPM. Points must be kept sorted by temperature. The curve can
/// drive one fan or several fans at once (`fanIndices`).
public struct FanCurve: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var fanIndices: [Int]   // fans (0-based) this curve drives
    public var sensorKey: String   // FourCC of the temperature sensor
    public var points: [CurvePoint]
    public var isEnabled: Bool

    public init(id: UUID = UUID(),
                name: String,
                fanIndices: [Int],
                sensorKey: String,
                points: [CurvePoint] = [],
                isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.fanIndices = fanIndices.sorted()
        self.sensorKey = sensorKey
        self.points = points.sorted { $0.temperatureC < $1.temperatureC }
        self.isEnabled = isEnabled
    }

    /// Convenience for a curve that drives a single fan.
    public init(id: UUID = UUID(),
                name: String,
                fanIndex: Int,
                sensorKey: String,
                points: [CurvePoint] = [],
                isEnabled: Bool = true) {
        self.init(id: id,
                  name: name,
                  fanIndices: [fanIndex],
                  sensorKey: sensorKey,
                  points: points,
                  isEnabled: isEnabled)
    }

    /// True if the curve targets the given fan index.
    public func targets(_ index: Int) -> Bool {
        fanIndices.contains(index)
    }

    /// Points sorted ascending by temperature.
    public var sortedPoints: [CurvePoint] {
        points.sorted { $0.temperatureC < $1.temperatureC }
    }

    // MARK: - Codable (backward compatible with `fanIndex`)

    private enum CodingKeys: String, CodingKey {
        case id, name, fanIndices, sensorKey, points, isEnabled
    }
    private enum LegacyKeys: String, CodingKey {
        case fanIndex
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        if let indices = try c.decodeIfPresent([Int].self, forKey: .fanIndices), !indices.isEmpty {
            fanIndices = indices.sorted()
        } else if let index = try legacy.decodeIfPresent(Int.self, forKey: .fanIndex) {
            fanIndices = [index]
        } else {
            fanIndices = []
        }
        sensorKey = try c.decode(String.self, forKey: .sensorKey)
        points = try c.decodeIfPresent([CurvePoint].self, forKey: .points) ?? []
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(fanIndices, forKey: .fanIndices)
        try c.encode(sensorKey, forKey: .sensorKey)
        try c.encode(points, forKey: .points)
        try c.encode(isEnabled, forKey: .isEnabled)
    }
}

/// Evaluates a `FanCurve` against a live temperature reading.
public enum CurveEvaluator {

    /// Deadband in degrees C applied at the curve's *entry* point.
    /// The fan only releases back to auto once the temperature drops below
    /// (firstPointTemperature - deadband). Prevents flapping around the
    /// knee of the curve.
    public static let deadband: Double = 3.0

    /// Evaluate the curve.
    ///
    /// - Returns: `nil` to release the fan to auto, otherwise the target RPM
    ///   (already clamped to `minRPM...maxRPM`).
    ///
    /// - Note: piecewise-linear interpolation between control points. Below
    ///   the first point the fan is released to auto; above the last point
    ///   it holds the last point's RPM.
    public static func evaluate(curve: FanCurve,
                                temperature: Double,
                                minRPM: Double,
                                maxRPM: Double,
                                currentlyActive: Bool) -> Double? {
        let points = curve.sortedPoints
        guard !points.isEmpty else { return nil }
        guard maxRPM > 0 else { return nil }

        let first = points[0]

        // Below the first point: auto, unless we've been holding the curve
        // and haven't yet dropped below the deadband (hysteresis).
        if temperature < first.temperatureC {
            if currentlyActive && temperature >= (first.temperatureC - deadband) {
                // Hold at the first point's RPM until we cross the deadband.
                return clamp(first.rpm, min: minRPM, max: maxRPM)
            }
            return nil
        }

        // Above the last point: hold last point RPM.
        let last = points[points.count - 1]
        if temperature >= last.temperatureC {
            return clamp(last.rpm, min: minRPM, max: maxRPM)
        }

        // Linear interpolation between the bracketing points.
        for i in 1..<points.count {
            let a = points[i - 1]
            let b = points[i]
            if temperature <= b.temperatureC {
                let t = (temperature - a.temperatureC) / (b.temperatureC - a.temperatureC)
                let rpm = a.rpm + t * (b.rpm - a.rpm)
                return clamp(rpm, min: minRPM, max: maxRPM)
            }
        }

        return clamp(last.rpm, min: minRPM, max: maxRPM)
    }

    private static func clamp(_ v: Double, min: Double, max: Double) -> Double {
        Swift.min(Swift.max(v, min), max)
    }
}