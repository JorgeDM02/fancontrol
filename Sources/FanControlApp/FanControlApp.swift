import SwiftUI
import AppKit
import FanControlCore

@main
struct FanControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("FanControl", id: "main") {
            DashboardRoot(vm: appDelegate.vm)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView(vm: appDelegate.vm, settings: .shared)
        }

        MenuBarExtra {
            MenuBarContent(vm: appDelegate.vm)
        } label: {
            MenuBarLabel(vm: appDelegate.vm)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Top-level window content.
struct DashboardRoot: View {
    @ObservedObject var vm: DashboardViewModel
    @State private var tab: DashboardTab = .monitor

    init(vm: DashboardViewModel) {
        self.vm = vm
    }

    var body: some View {
        VStack(spacing: 0) {
            HelperBar(vm: vm)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            Picker("", selection: $tab) {
                ForEach(DashboardTab.allCases) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 420)
            .padding(.top, 10)

            Group {
                switch tab {
                case .monitor:  MonitorView(vm: vm)
                case .fans:     FansView(vm: vm)
                case .curves:   CurvesView(vm: vm)
                case .presets:  PresetsView(vm: vm)
                case .settings: SettingsView(vm: vm, settings: .shared)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            StatusBar(vm: vm)
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}

enum DashboardTab: String, CaseIterable, Identifiable {
    case monitor
    case fans
    case curves
    case presets
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monitor:  return "Monitor"
        case .fans:     return "Fans"
        case .curves:   return "Curves"
        case .presets:  return "Presets"
        case .settings: return "Settings"
        }
    }
}

// MARK: - Helper bar

struct HelperBar: View {
    @ObservedObject var vm: DashboardViewModel
    @State private var busy = false

    var body: some View {
        HStack {
            Image(systemName: "fan.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            Text("FanControl")
                .font(.headline)

            Spacer()

            if vm.helperStatus.isRunning {
                Label("Helper: \(vm.helperStatus.shortText)", systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green)
                    .font(.callout)
            } else if case .installedButUnreachable = vm.helperStatus {
                Label("Helper installed but unreachable", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.callout)
            } else if case .notInstalled = vm.helperStatus {
                Label("No privileged helper", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.callout)
            } else {
                ProgressView().controlSize(.small)
            }

            if vm.helperStatus.isRunning {
                if !vm.isTakingControl {
                    Button("Take control") {
                        Task { await vm.takeControl() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button("Release control") {
                        vm.releaseControlFromUI()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if case .notInstalled = vm.helperStatus, !busy {
                Button("Install helper…") {
                    busy = true
                    Task {
                        await vm.installHelper()
                        busy = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else if case .installedButUnreachable = vm.helperStatus, !busy {
                Button("Reinstall helper…") {
                    busy = true
                    Task {
                        await vm.uninstallHelper()
                        await vm.installHelper()
                        busy = false
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Status bar

struct StatusBar: View {
    @ObservedObject var vm: DashboardViewModel

    var body: some View {
        HStack(spacing: 16) {
            if let t = vm.cpuTemp, let label = vm.cpuTempLabel {
                Label("\(label) \(Int(t))°C", systemImage: "cpu")
                    .font(.callout)
                    .monospacedDigit()
            }
            ForEach(vm.fans) { fan in
                Label("\(Int(fan.actualRPM)) rpm", systemImage: "fan")
                    .font(.callout)
                    .monospacedDigit()
            }
            Spacer()
            if let msg = vm.lastMessage {
                Text(msg)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

// MARK: - App delegate

/// Owns the view model so its lifecycle is tied to the application, not
/// to any individual SwiftUI scene. Keeps the menu-bar extra alive when
/// the main window is closed.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let vm: DashboardViewModel

    override init() {
        self.vm = DashboardViewModel()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        vm.start()

        // Started at login with "Start minimized": dock the main window so
        // it doesn't steal focus. Only applies when we're not the active app.
        if AppSettings.shared.launchAtLogin && AppSettings.shared.launchMinimized {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if !NSApp.isActive {
                    NSApp.windows.first { $0.canBecomeMain }?.miniaturize(nil)
                }
            }
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Best-effort: hand fans back to the system. If this fires too late,
        // the helper's 10s watchdog reverts everything to auto anyway.
        if vm.isTakingControl {
            let indices = vm.engagedFanIndices()
            for index in indices {
                Task { _ = await vm.client.setFanAuto(index: index) }
            }
        }
        vm.stop()
        return .terminateNow
    }

    @objc private func windowDidBecomeMain(_ note: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    @objc private func windowWillClose(_ note: Notification) {
        guard let window = note.object as? NSWindow, window.canBecomeMain else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let hasVisibleMain = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
            if !hasVisibleMain {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

// MARK: - Menu bar label

/// Shows the fan icon plus, when enabled, a compact live temperature readout
/// for the user-selected sensor source.
struct MenuBarLabel: View {
    @ObservedObject var vm: DashboardViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "fan")
            if vm.settings.showMenuTemp, let sensor = vm.menuBarTemp {
                Text("\(Int(sensor.celsius))°C")
                    .font(.system(size: 11))
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Menu bar content

struct MenuBarContent: View {
    @ObservedObject var vm: DashboardViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if vm.settings.showMenuTemp, let sensor = vm.menuBarTemp {
                Label("\(sensor.label) \(Int(sensor.celsius))°C", systemImage: "thermometer")
            }
            ForEach(vm.fans) { fan in
                Label("Fan \(fan.index): \(Int(fan.actualRPM)) rpm", systemImage: "fan")
            }

            Divider()

            Button("Open FanControl") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button(vm.isTakingControl ? "Release control" : "Take control") {
                if vm.isTakingControl {
                    vm.releaseControlFromUI()
                } else {
                    Task { await vm.takeControl() }
                }
            }
            .disabled(!vm.helperStatus.isRunning)

            Divider()

            if !vm.presetStore.presets.isEmpty {
                Menu("Apply preset") {
                    ForEach(vm.presetStore.presets) { preset in
                        Button(preset.name) {
                            vm.applyPreset(preset)
                        }
                    }
                }
            }

            if !vm.curveStore.curves.isEmpty {
                Menu("Curves") {
                    ForEach(vm.curveStore.curves) { curve in
                        Button("\(curve.isEnabled ? "Disengage" : "Engage") \(curve.name)") {
                            if curve.isEnabled {
                                vm.disengageCurve(curve)
                            } else {
                                vm.engageCurve(curve)
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Quit FanControl") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.vertical, 4)
        .onAppear {
            vm.start()
        }
    }
}