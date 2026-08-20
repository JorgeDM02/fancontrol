import Foundation
import FanControlCore

/// Persists `FanCurve` items to `~/Library/Application Support/FanControl/curves.json`.
@MainActor
final class CurveStore: ObservableObject {
    @Published private(set) var curves: [FanCurve] = []

    private let url: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FanControl", isDirectory: true)
        self.url = base.appendingPathComponent("curves.json")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        load()
    }

    @discardableResult
    func add(name: String, fanIndices: [Int], sensorKey: String, points: [CurvePoint]) -> FanCurve {
        let curve = FanCurve(name: name, fanIndices: fanIndices, sensorKey: sensorKey, points: points)
        curves.append(curve)
        persist()
        return curve
    }

    func update(_ curve: FanCurve) {
        if let i = curves.firstIndex(where: { $0.id == curve.id }) {
            curves[i] = curve
            persist()
        } else {
            curves.append(curve)
            persist()
        }
    }

    func delete(_ curve: FanCurve) {
        curves.removeAll { $0.id == curve.id }
        persist()
    }

    func rename(_ curve: FanCurve, to name: String) {
        var copy = curve
        copy.name = name
        update(copy)
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([FanCurve].self, from: data) else {
            curves = []
            return
        }
        curves = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func persist() {
        curves.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard let data = try? JSONEncoder().encode(curves) else { return }
        try? data.write(to: url, options: .atomic)
    }
}