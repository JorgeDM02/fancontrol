import SwiftUI
import FanControlCore

/// Live readings: fans summary + temperature sensors.
struct MonitorView: View {
    @ObservedObject var vm: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !vm.hasFans {
                ContentUnavailableView(
                    "No fans detected",
                    systemImage: "fan.slash",
                    description: Text("This machine reports no SMC fans. Temperature monitoring is still available.")
                )
            }

            if !vm.fans.isEmpty {
                HStack(spacing: 12) {
                    ForEach(vm.fans) { fan in
                        FanCard(reading: fan)
                    }
                }
            }

            Divider()

            Text("Temperature sensors (\(vm.sensors.count))")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(vm.sensors) { sensor in
                        HStack {
                            Text(sensor.label)
                                .font(.callout)
                            if sensor.key != sensor.label {
                                Text(sensor.key)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(sensor.celsius, specifier: "%.1f")°C")
                                .font(.callout.monospacedDigit())
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
        }
        .padding(14)
    }
}

struct FanCard: View {
    let reading: FanReading

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fan \(reading.index)")
                .font(.headline)
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(reading.actualRPM))")
                    .font(.title.monospacedDigit())
                Text("rpm")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            Text("target \(Int(reading.targetRPM)) rpm · \(reading.mode == 0 ? "auto" : "manual")")
                .font(.caption)
                .foregroundColor(.secondary)
            if !reading.readingsValid {
                Label("readings degraded", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}