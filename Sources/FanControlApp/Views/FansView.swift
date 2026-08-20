import SwiftUI
import FanControlCore

/// Per-fan manual control: Auto / Custom RPM / Full speed.
struct FansView: View {
    @ObservedObject var vm: DashboardViewModel
    @State private var draftRPM: [Int: Double] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !vm.helperStatus.isRunning {
                ContentUnavailableView(
                    "Fan control needs the helper",
                    systemImage: "lock.shield",
                    description: Text("Install the privileged helper (top bar) before you can change fan speeds.")
                )
            } else {
                Text("Set a fixed speed, or rely on Curves / Presets for automation. Fans revert to system control when the app quits or crashes.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(vm.fans) { fan in
                        FanControlCard(vm: vm, fan: fan, draft: draftBinding(fan.index))
                    }
                }
            }
        }
        .padding(14)
    }

    private func draftBinding(_ index: Int) -> Binding<Double> {
        Binding<Double>(
            get: { draftRPM[index] ?? currentRPM(index) },
            set: { draftRPM[index] = $0 }
        )
    }

    private func currentRPM(_ index: Int) -> Double {
        vm.fans.first { $0.index == index }?.actualRPM ?? 1000
    }
}

struct FanControlCard: View {
    @ObservedObject var vm: DashboardViewModel
    let fan: FanReading
    @Binding var draft: Double

    private var selectedMode: FanControlCardMode {
        switch vm.intent(for: fan.index) {
        case .custom:   return .custom
        case .fullSpeed:return .fullSpeed
        default:        return .auto
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Fan \(fan.index)")
                    .font(.headline)
                Spacer()
                Text("\(Int(fan.actualRPM)) rpm now")
                    .font(.callout.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Picker("Mode", selection: Binding(
                get: { selectedMode },
                set: { newMode in
                    switch newMode {
                    case .auto:
                        vm.setFanAuto(fan.index)
                    case .custom:
                        vm.setFanCustom(fan.index, rpm: draft)
                    case .fullSpeed:
                        vm.setFanFullSpeed(fan.index)
                    }
                }
            )) {
                Text("Auto").tag(FanControlCardMode.auto)
                Text("Custom").tag(FanControlCardMode.custom)
                Text("Full speed").tag(FanControlCardMode.fullSpeed)
            }
            .pickerStyle(.segmented)

            if selectedMode == .custom {
                HStack(spacing: 10) {
                    Slider(
                        value: Binding(
                            get: { draft },
                            set: { newValue in
                                draft = newValue
                                vm.setFanCustom(fan.index, rpm: newValue)
                            }
                        ),
                        in: fan.minRPM...fan.maxRPM,
                        step: 50
                    )
                    Text("\(Int(draft))")
                        .font(.callout.monospacedDigit())
                        .frame(width: 48, alignment: .trailing)
                }
                .onAppear {
                    draft = vm.currentTarget(for: fan.index, fallback: fan.actualRPM)
                }
            }

            HStack(spacing: 8) {
                Text("range \(Int(fan.minRPM))–\(Int(fan.maxRPM)) rpm")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !fan.readingsValid {
                    Label("readings degraded", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

enum FanControlCardMode: Hashable {
    case auto
    case custom
    case fullSpeed
}