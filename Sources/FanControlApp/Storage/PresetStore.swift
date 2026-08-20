import Foundation
import FanControlCore

/// Persists `FanPreset` items to `~/Library/Application Support/FanControl/presets.json`.
@MainActor
final class PresetStore: ObservableObject {
    @Published private(set) var presets: [FanPreset] = []

    private let url: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FanControl", isDirectory: true)
        self.url = base.appendingPathComponent("presets.json")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        load()
    }

    func save(_ preset: FanPreset) {
        if let i = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[i] = preset
        } else {
            presets.append(preset)
        }
        persist()
    }

    func add(name: String, settings: [FanSetting]) -> FanPreset {
        let preset = FanPreset(name: name, settings: settings)
        presets.append(preset)
        persist()
        return preset
    }

    func update(_ preset: FanPreset) {
        if let i = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[i] = preset
            persist()
        }
    }

    func delete(_ preset: FanPreset) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    func duplicate(_ preset: FanPreset) {
        var copy = preset
        copy.id = UUID()
        copy.name = "\(preset.name) copy"
        presets.append(copy)
        persist()
    }

    func rename(_ preset: FanPreset, to name: String) {
        var copy = preset
        copy.name = name
        update(copy)
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([FanPreset].self, from: data) else {
            presets = []
            return
        }
        presets = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func persist() {
        presets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard let data = try? JSONEncoder().encode(presets) else { return }
        try? data.write(to: url, options: .atomic)
    }
}