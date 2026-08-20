import SwiftUI
import FanControlCore

/// Saved per-fan configurations you can re-apply in one click.
struct PresetsView: View {
    @ObservedObject var vm: DashboardViewModel
    @State private var showSaveSheet = false
    @State private var pendingDelete: FanPreset?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Presets")
                    .font(.headline)
                Spacer()
                Button {
                    showSaveSheet = true
                } label: {
                    Label("Save current setup…", systemImage: "square.and.arrow.down")
                }
                .disabled(!vm.isTakingControl)
            }

            if vm.presetStore.presets.isEmpty {
                ContentUnavailableView(
                    "No presets yet",
                    systemImage: "tray",
                    description: Text("Take control, set the fans the way you like them, then save it as a preset here.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.presetStore.presets) { preset in
                            presetRow(preset)
                        }
                    }
                }
            }
        }
        .padding(14)
        .sheet(isPresented: $showSaveSheet) {
            SavePresetSheet(vm: vm) { name in
                vm.saveCurrentAsPreset(named: name)
            }
        }
        .confirmationDialog(
            "Delete this preset?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let p = pendingDelete {
                    vm.presetStore.delete(p)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private func presetRow(_ preset: FanPreset) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.headline)
                Text(summary(preset))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Apply") {
                vm.applyPreset(preset)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!vm.isTakingControl)

            Menu {
                Button("Duplicate") { vm.presetStore.duplicate(preset) }
                Button("Rename…") { renameFlow(preset) }
                Divider()
                Button("Delete", role: .destructive) { pendingDelete = preset }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .controlSize(.small)
            .menuStyle(.borderlessButton)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func summary(_ preset: FanPreset) -> String {
        preset.settings
            .sorted { $0.fanIndex < $1.fanIndex }
            .map { setting in
                switch setting.mode {
                case .auto:      return "F\(setting.fanIndex): auto"
                case .custom:    return "F\(setting.fanIndex): \(Int(setting.rpm)) rpm"
                case .fullSpeed: return "F\(setting.fanIndex): max"
                }
            }
            .joined(separator: " · ")
    }

    private func renameFlow(_ preset: FanPreset) {
        // Simple inline rename via an alert with a text field.
        let alert = NSAlert()
        alert.messageText = "Rename preset"
        alert.informativeText = "Enter a new name for “\(preset.name)”."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = preset.name
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty {
            vm.presetStore.rename(preset, to: field.stringValue)
        }
    }
}

/// Asks for the name of the preset to save.
struct SavePresetSheet: View {
    @ObservedObject var vm: DashboardViewModel
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = "Quiet"
    @State private var detail = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save current fan setup")
                .font(.headline)

            TextField("Preset name", text: $name)
                .textFieldStyle(.roundedBorder)

            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            detail = vm.presetPreamble()
        }
    }
}