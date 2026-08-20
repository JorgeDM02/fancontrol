import SwiftUI
import FanControlCore

/// Preferences window: startup behaviour and the menu-bar temperature widget.
struct SettingsView: View {
    @ObservedObject var vm: DashboardViewModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open FanControl at login",
                       isOn: $settings.launchAtLogin)

                Toggle("Start minimized",
                       isOn: $settings.launchMinimized)
                    .disabled(!settings.launchAtLogin)

                if let error = settings.loginItemError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Section("Menu bar temperature") {
                Toggle("Show temperature in the menu bar",
                       isOn: $settings.showMenuTemp)

                Picker("Source", selection: $settings.menuTempSensorKey) {
                    Text("Auto (CPU)").tag("")
                    ForEach(vm.sensors) { sensor in
                        Text("\(sensor.label) (\(sensor.key))")
                            .tag(sensor.key)
                    }
                }
                .disabled(!settings.showMenuTemp)
                .onChange(of: settings.showMenuTemp) { _, show in
                    // If just enabled with no explicit source, pin the CPU sensor.
                    if show && settings.menuTempSensorKey.isEmpty,
                       let cpu = vm.sensors.first(where: { $0.category == .cpu }) {
                        settings.menuTempSensorKey = cpu.key
                    }
                }

                if settings.showMenuTemp, let sensor = vm.menuBarTemp {
                    Text("Preview: \(sensor.label) \(Int(sensor.celsius))°C")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420, height: 320)
    }
}