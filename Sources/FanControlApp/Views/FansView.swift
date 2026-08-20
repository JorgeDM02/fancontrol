import SwiftUI
import FanControlCore

/// Per-fan manual control: Auto / Custom RPM / Full speed.
/// By default one control drives every fan; flip the switch to set each fan
/// individually.
struct FansView: View {
    @ObservedObject var vm: DashboardViewModel
    @State private var draftRPM: [Int: Double] = [:]
    @State private var applyToAll = true
    @State private var allDraftRPM: Double = 1000

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !vm.helperStatus.isRunning {
                ContentUnavailableView(
                    "Fan control needs the helper",
                    systemImage: "lock.shield",
                    description: Text("Install the privileged helper (top bar) before you can change fan speeds.")
                )
            } else {
                Toggle(isOn: $applyToAll) {
                    Text("Apply to all fans")
                }
                .toggleStyle(.switch)

                Text("Set a fixed speed, or rely on Curves / Presets for automation. Fans revert to system control when the app quits or crashes.")
                    .font(.callout)
                    .foregroundColor(.secondary)

                if applyToAll {
                    AllFansControl(vm: vm, draft: $allDraftRPM)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(vm.fans) { fan in
                                FanControlCard(vm: vm, fan: fan, draft: draftBinding(fan.index))
                            }
                        }
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

/// Single control that drives every fan at once.
struct AllFansControl: View {
    @ObservedObject var vm: DashboardViewModel
    @Binding var draft: Double

    private var mode: FanControlCardMode {
        let m = vm.fans.map { fan -> FanControlCardMode in
            switch vm.intent(for: fan.index) {
            case .custom:    return .custom
            case .fullSpeed: return .fullSpeed
            default:         return .auto
            }
        }
        guard let first = m.first, m.allSatisfy({ $0 == first }) else { return .auto }
        return first
    }

    private var sliderRange: ClosedRange<Double> {
        guard let lo = vm.fans.map(\.minRPM).min(),
              let hi = vm.fans.map(\.maxRPM).max() else { return 0...1000 }
        return lo...hi
    }

    private var firstFan: FanReading? { vm.fans.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("All fans (\(vm.fans.count))")
                    .font(.headline)
                Spacer()
                Text("\(vm.fans.map { Int($0.actualRPM) }.max() ?? 0) rpm max now")
                    .font(.callout.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Picker("Mode", selection: Binding(
                get: { mode },
                set: { newMode in
                    switch newMode {
                    case .auto:      vm.setAllFanAuto()
                    case .custom:    vm.setAllFanCustom(rpm: draft)
                    case .fullSpeed: vm.setAllFanFullSpeed()
                    }
                }
            )) {
                Text("Auto").tag(FanControlCardMode.auto)
                Text("Custom").tag(FanControlCardMode.custom)
                Text("Full speed").tag(FanControlCardMode.fullSpeed)
            }
            .pickerStyle(.segmented)

            if mode == .custom {
                HStack(spacing: 10) {
                    Slider(
                        value: Binding(
                            get: { draft },
                            set: { newValue in
                                draft = newValue
                                vm.setAllFanCustom(rpm: newValue)
                            }
                        ),
                        in: sliderRange,
                        step: 50
                    )
                    Text("\(Int(draft))")
                        .font(.callout.monospacedDigit())
                        .frame(width: 48, alignment: .trailing)
                }
                .onAppear {
                    if let fan = firstFan {
                        draft = vm.currentTarget(for: fan.index, fallback: fan.actualRPM)
                    }
                }
            }

            let lo = sliderRange.lowerBound
            let hi = sliderRange.upperBound
            Text("range \(Int(lo))–\(Int(hi)) rpm across all fans")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
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