import Foundation

/// How a single fan should be set when a preset is applied.
public enum PresetFanMode: String, Codable, Sendable, Hashable {
    case auto
    case custom          // fixed RPM from the preset
    case fullSpeed
}

/// One fan's setting inside a `FanPreset`.
public struct FanSetting: Codable, Sendable, Hashable {
    public var fanIndex: Int
    public var mode: PresetFanMode
    public var rpm: Double   // used when mode == .custom

    public init(fanIndex: Int, mode: PresetFanMode, rpm: Double) {
        self.fanIndex = fanIndex
        self.mode = mode
        self.rpm = rpm
    }
}

/// A saved, named snapshot of per-fan settings that can be applied in one
/// click (or from the menu bar).
public struct FanPreset: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var settings: [FanSetting]

    public init(id: UUID = UUID(), name: String, settings: [FanSetting] = []) {
        self.id = id
        self.name = name
        self.settings = settings
    }
}