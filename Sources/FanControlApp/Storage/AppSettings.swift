import Foundation
import ServiceManagement
import Combine

/// User-facing preferences, persisted to UserDefaults.
///
/// - `launchAtLogin` — whether the app starts at login. Managed through the
///   modern `SMAppService.mainApp` API (System Settings → Login Items).
/// - `launchMinimized` — when starting at login, begin docked/minimized
///   instead of stealing focus. Only meaningful if `launchAtLogin` is on.
/// - `showMenuTemp` — show a live temperature readout in the menu bar.
/// - `menuTempSensorKey` — SMC key of the sensor to display (empty = auto
///   pick the CPU sensor).
@MainActor
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private enum Key {
        static let launchAtLogin = "settings.launchAtLogin"
        static let launchMinimized = "settings.launchMinimized"
        static let showMenuTemp = "settings.showMenuTemp"
        static let menuTempSensorKey = "settings.menuTempSensorKey"
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
            applyLoginItem(enable: launchAtLogin)
        }
    }

    @Published var launchMinimized: Bool {
        didSet { defaults.set(launchMinimized, forKey: Key.launchMinimized) }
    }

    @Published var showMenuTemp: Bool {
        didSet { defaults.set(showMenuTemp, forKey: Key.showMenuTemp) }
    }

    @Published var menuTempSensorKey: String {
        didSet { defaults.set(menuTempSensorKey, forKey: Key.menuTempSensorKey) }
    }

    /// Non-nil when the last login-item update failed (e.g. app not in /Applications).
    @Published var loginItemError: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        let storedMinimized = defaults.object(forKey: Key.launchMinimized) as? Bool
        self.launchMinimized = storedMinimized ?? true
        self.showMenuTemp = defaults.bool(forKey: Key.showMenuTemp)
        self.menuTempSensorKey = defaults.string(forKey: Key.menuTempSensorKey) ?? ""
        if SMAppService.mainApp.status == .enabled {
            self.launchAtLogin = true
            defaults.set(true, forKey: Key.launchAtLogin)
        }
    }

    private func applyLoginItem(enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = "Could not \(enable ? "enable" : "disable") login item: \(error.localizedDescription)"
        }
    }
}