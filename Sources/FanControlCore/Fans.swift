import Foundation

/// Snapshot of a single fan's state.
public struct FanReading: Sendable, Hashable, Codable, Identifiable {
    public let index: Int       // 0, 1, ...
    public let actualRPM: Double
    public let targetRPM: Double
    public let minRPM: Double
    public let maxRPM: Double
    /// Fan mode: 0 = auto (system-controlled), 1 = manual (this app wrote it).
    public let mode: UInt8
    /// True if the fan's "current" readings appear valid.
    public let readingsValid: Bool

    public var id: Int { index }

    public init(index: Int, actualRPM: Double, targetRPM: Double,
                minRPM: Double, maxRPM: Double, mode: UInt8,
                readingsValid: Bool) {
        self.index = index
        self.actualRPM = actualRPM
        self.targetRPM = targetRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.mode = mode
        self.readingsValid = readingsValid
    }
}

public final class FanReader {
    private let smc: SMC

    public init(smc: SMC = .shared) {
        self.smc = smc
    }

    /// Number of fans reported by `FNum`.
    public func count() -> Int {
        return Int(smc.readUInt8(FourCC.make("FNum")) ?? 0)
    }

    public func readAll() -> [FanReading] {
        let n = count()
        guard n > 0 else { return [] }
        var out: [FanReading] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            if let r = read(index: i) {
                out.append(r)
            }
        }
        return out
    }

    public func read(index: Int) -> FanReading? {
        guard let acKey = Self.fanKey(index: index, suffix: "Ac"),
              let tgKey = Self.fanKey(index: index, suffix: "Tg"),
              let mnKey = Self.fanKey(index: index, suffix: "Mn"),
              let mxKey = Self.fanKey(index: index, suffix: "Mx"),
              let mdKey = smc.fanModeKey(forIndex: index)
        else { return nil }

        let ac = smc.readFloat(acKey).map(Double.init) ?? 0
        let tg = smc.readFloat(tgKey).map(Double.init) ?? 0
        let mn = smc.readFloat(mnKey).map(Double.init) ?? 0
        let mx = smc.readFloat(mxKey).map(Double.init) ?? 0
        let md = smc.readUInt8(mdKey) ?? 0

        // When the driver is latched into manual mode and reads degrade,
        // actual can read 0 while min > 0 and mode == 0. Detect it so the
        // UI can show a banner instead of "fan off".
        let validReadings = !(md == 0 && mn > 0 && ac == 0)

        return FanReading(
            index: index,
            actualRPM: ac,
            targetRPM: tg,
            minRPM: mn,
            maxRPM: mx,
            mode: md,
            readingsValid: validReadings
        )
    }

    /// Build a FourCC like "F0Ac" from index 0 and suffix "Ac".
    public static func fanKey(index: Int, suffix: String) -> UInt32? {
        guard index >= 0, index < 10 else { return nil }
        guard suffix.utf8.count == 2 else { return nil }
        let s = "F\(index)\(suffix)"
        return FourCC.makeRuntime(s)
    }
}