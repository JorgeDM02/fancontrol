import SwiftUI
import FanControlCore

/// List of curves on the left, editor + interactive graph on the right.
struct CurvesView: View {
    @ObservedObject var vm: DashboardViewModel
    @State private var selectedID: UUID?
    @State private var showNewForm = false
    @State private var editingID: UUID?

    private func fansLabel(_ curve: FanCurve) -> String {
        curve.fanIndices.map { "Fan \($0)" }.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 0) {
            // ---- List ----
            VStack(alignment: .leading, spacing: 0) {
                Text("Fan curves")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                List(selection: $selectedID) {
                    ForEach(vm.curveStore.curves) { curve in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(curve.name)
                            Text("\(fansLabel(curve)) · \(curve.sensorKey) · \(curve.points.count) pts")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .tag(curve.id)
                        .contextMenu {
                            Button("Edit…") { editingID = curve.id }
                            Button(role: .destructive) {
                                vm.deleteCurve(curve)
                                if selectedID == curve.id {
                                    selectedID = vm.curveStore.curves.first?.id
                                }
                            } label: {
                                Label("Delete curve", systemImage: "trash")
                            }
                        }
                        .onTapGesture(count: 2) {
                            editingID = curve.id
                        }
                    }
                }
                .listStyle(.sidebar)

                Button {
                    showNewForm = true
                } label: {
                    Label("New curve", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(12)
            }
            .frame(width: 230)

            Divider()

            // ---- Editor ----
            Group {
                if let curve = vm.curveStore.curves.first(where: { $0.id == selectedID }) {
                    CurveSummaryView(vm: vm, curve: curve) {
                        editingID = curve.id
                    }
                } else if !vm.curveStore.curves.isEmpty {
                    ContentUnavailableView(
                        "Select a curve",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Pick a curve from the list to edit it.")
                    )
                } else {
                    ContentUnavailableView(
                        "No curves yet",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Create a curve that maps a temperature to a fan speed.")
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showNewForm) {
            NewCurveSheet(vm: vm) { curve in
                vm.curveStore.add(
                    name: curve.name,
                    fanIndices: curve.fanIndices,
                    sensorKey: curve.sensorKey,
                    points: curve.points
                )
                selectedID = curve.id
            }
        }
        .sheet(isPresented: Binding(
            get: { editingID != nil },
            set: { if !$0 { editingID = nil } }
        )) {
            if let curve = vm.curveStore.curves.first(where: { $0.id == editingID }) {
                CurveEditorSheet(vm: vm, curve: curve, onClose: { editingID = nil })
            }
        }
        .task {
            if selectedID == nil { selectedID = vm.curveStore.curves.first?.id }
        }
    }
}

// MARK: - Summary (right pane)

/// Compact read-only summary of a selected curve; editing happens in a
/// sheet so the main window's navigation/tab bar is never replaced.
struct CurveSummaryView: View {
    @ObservedObject var vm: DashboardViewModel
    let curve: FanCurve
    var onEdit: () -> Void = {}

    private var fan: FanReading? { vm.fans.first { curve.fanIndices.contains($0.index) } }
    private var liveTemp: Double? { vm.sensors.first { $0.key == curve.sensorKey }?.celsius }
    private var isEngaged: Bool {
        curve.fanIndices.contains { vm.intent(for: $0) == .curve(curve.id) }
    }

    private var evaluated: Double? {
        guard let t = liveTemp, let fan else { return nil }
        return CurveEvaluator.evaluate(
            curve: curve,
            temperature: t,
            minRPM: fan.minRPM,
            maxRPM: fan.maxRPM,
            currentlyActive: isEngaged
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(curve.name)
                    .font(.title2).bold()
                Spacer()
                Button("Edit…") { onEdit() }
                    .buttonStyle(.borderedProminent)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Fans").foregroundStyle(.secondary)
                    Text(curve.fanIndices.map { "Fan \($0)" }.joined(separator: ", "))
                }
                GridRow {
                    Text("Sensor").foregroundStyle(.secondary)
                    Text("\(curve.sensorKey)\(liveTemp.map { String(format: " — %.1f°C", $0) } ?? "")")
                }
                GridRow {
                    Text("Points").foregroundStyle(.secondary)
                    Text("\(curve.points.count)  (\(curve.points.map { "\(Int($0.temperatureC))°→\(Int($0.rpm))" }.joined(separator: ", ")))")
                }
                GridRow {
                    Text("Current").foregroundStyle(.secondary)
                    if let rpm = evaluated {
                        Text("\(Int(rpm)) rpm target")
                    } else {
                        Text("fan → auto (below curve)").foregroundStyle(.secondary)
                    }
                }
            }
            .font(.callout)

            Toggle(isOn: Binding(
                get: { isEngaged },
                set: { engage in
                    if engage { vm.engageCurve(curve) } else { vm.disengageCurve(curve) }
                }
            )) {
                Text(isEngaged ? "Engaged" : "Disengaged")
            }
            .toggleStyle(.switch)
            .disabled(!vm.helperStatus.isRunning)

            Spacer()

            Text("Double-click a curve in the list (or Edit…) to open the editor. Edits save automatically.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Editor sheet

/// Full curve editor presented as a modal sheet. The main window (and its
/// tab bar) stays exactly as it was, and Done brings you back to it.
struct CurveEditorSheet: View {
    @ObservedObject var vm: DashboardViewModel
    let curve: FanCurve
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit curve")
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    vm.deleteCurve(curve)
                    onClose()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button("Done") { onClose() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            CurveEditorView(vm: vm, curve: curve)
        }
        .frame(width: 780, height: 640)
    }
}

// MARK: - Editor

struct CurveEditorView: View {
    @ObservedObject var vm: DashboardViewModel
    let curve: FanCurve

    @State private var name: String = ""
    @State private var fanSet: Set<Int> = []
    @State private var sensorKey: String = ""

    private var fan: FanReading? { vm.fans.first { curve.fanIndices.contains($0.index) } }
    private var liveTemp: Double? { vm.sensors.first { $0.key == curve.sensorKey }?.celsius }
    private var isEngaged: Bool {
        curve.fanIndices.contains { vm.intent(for: $0) == .curve(curve.id) }
    }

    private var evaluated: Double? {
        guard let t = liveTemp, let fan else { return nil }
        return CurveEvaluator.evaluate(
            curve: curve,
            temperature: t,
            minRPM: fan.minRPM,
            maxRPM: fan.maxRPM,
            currentlyActive: isEngaged
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Curve name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onChange(of: name) { update() }

                Spacer()

                Toggle(isOn: Binding(
                    get: { isEngaged },
                    set: { engage in
                        if engage { vm.engageCurve(curve) }
                        else { vm.disengageCurve(curve) }
                    }
                )) {
                    Text(isEngaged ? "Engaged" : "Disengaged")
                }
                .toggleStyle(.switch)
                .disabled(!vm.helperStatus.isRunning)
            }

            HStack(spacing: 12) {
                Text("Fans")
                ForEach(vm.fans, id: \.index) { fan in
                    Toggle(isOn: Binding(
                        get: { fanSet.contains(fan.index) },
                        set: { on in
                            var next = fanSet
                            if on { next.insert(fan.index) } else { next.remove(fan.index) }
                            applyFans(next)
                        }
                    )) {
                        Text("Fan \(fan.index)")
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                if curve.fanIndices.isEmpty {
                    Text("Select at least one fan")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                Spacer()

                Picker("Sensor", selection: Binding(
                    get: { curve.sensorKey },
                    set: { sensorKey = $0; updateSensor($0) }
                )) {
                    ForEach(candidateSensors, id: \.key) { sensor in
                        Text("\(sensor.label) (\(sensor.key))").tag(sensor.key)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // ---- Graph ----
            if let fan {
                CurveGraphView(
                    points: curve.sortedPoints,
                    fanMin: fan.minRPM,
                    fanMax: fan.maxRPM,
                    currentTemp: liveTemp,
                    computedRPM: evaluated,
                    onMove: { pointID, temp, rpm in
                        movePoint(pointID, temp: temp, rpm: rpm)
                    },
                    onDelete: { pointID in
                        removePoint(pointID)
                    }
                )
                .frame(height: 260)
            }

            HStack {
                if let t = liveTemp {
                    Text("Sensor now: \(t, specifier: "%.1f")°C")
                }
                Spacer()
                if let rpm = evaluated {
                    Label("target \(Int(rpm)) rpm", systemImage: "fan")
                } else {
                    Text("fan → auto below curve")
                        .foregroundColor(.secondary)
                }
            }
            .font(.callout)
            .monospacedDigit()

            // ---- Points table ----
            HStack {
                Text("Control points — drag on the graph to move, ⌥-double-click to delete")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    let temp = (curve.sortedPoints.last?.temperatureC ?? 50) + 10
                    appendPoint(temp: temp, rpm: fan?.maxRPM ?? 6000)
                } label: {
                    Label("Add point", systemImage: "plus")
                }
                .controlSize(.small)
            }

            Table(curve.sortedPoints) {
                TableColumn("Temp °C") { point in
                    TextField("", value: Binding(
                        get: { point.temperatureC },
                        set: { movePoint(point.id, temp: $0, rpm: point.rpm) }
                    ), format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                TableColumn("RPM") { point in
                    TextField("", value: Binding(
                        get: { point.rpm },
                        set: { movePoint(point.id, temp: point.temperatureC, rpm: $0) }
                    ), format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }
                TableColumn("") { point in
                    Button(role: .destructive) {
                        removePoint(point.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .width(30)
            }
            .frame(height: 150)

            Text("Below the first point the fan returns to system (auto) control. Hysteresis keeps it engaged within 3°C of the first point.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .onAppear {
            name = curve.name
            fanSet = Set(curve.fanIndices)
            sensorKey = curve.sensorKey
        }
    }

    // MARK: - Sensor candidates

    private var candidateSensors: [SensorReading] {
        vm.sensors
    }

    // MARK: - Editing helpers

    private func movePoint(_ id: UUID, temp: Double, rpm: Double) {
        var copy = curve
        copy.points = curve.points.map { p in
            guard p.id == id else { return p }
            return CurvePoint(id: p.id, temperatureC: temp, rpm: rpm)
        }.sorted { $0.temperatureC < $1.temperatureC }
        vm.curveStore.update(copy)
    }

    private func appendPoint(temp: Double, rpm: Double) {
        var copy = curve
        let safeTemp = Swift.min(Swift.max(temp, 0), 130)
        let safeRPM = Swift.max(rpm, 0)
        copy.points.append(CurvePoint(temperatureC: safeTemp, rpm: safeRPM))
        copy.points.sort { $0.temperatureC < $1.temperatureC }
        vm.curveStore.update(copy)
    }

    private func removePoint(_ id: UUID) {
        var copy = curve
        copy.points.removeAll { $0.id == id }
        vm.curveStore.update(copy)
    }

    private func applyFans(_ indices: Set<Int>) {
        var copy = curve
        copy.fanIndices = indices.sorted()
        vm.curveStore.update(copy)
    }

    private func updateSensor(_ key: String) {
        var copy = curve
        copy.sensorKey = key
        vm.curveStore.update(copy)
    }

    private func update() {
        var copy = curve
        copy.name = name
        vm.curveStore.update(copy)
    }
}

// MARK: - New curve sheet

struct NewCurveSheet: View {
    @ObservedObject var vm: DashboardViewModel
    let onCreate: (FanCurve) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = "New curve"
    @State private var fanSet: Set<Int> = []
    @State private var sensorKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New fan curve")
                .font(.headline)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Apply to fans")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 12) {
                    ForEach(vm.fans, id: \.index) { fan in
                        Toggle("Fan \(fan.index)", isOn: Binding(
                            get: { fanSet.contains(fan.index) },
                            set: { on in
                                if on { fanSet.insert(fan.index) } else { fanSet.remove(fan.index) }
                            }
                        ))
                        .toggleStyle(.switch)
                    }
                }
            }

            Picker("Sensor", selection: $sensorKey) {
                ForEach(vm.sensors, id: \.key) { sensor in
                    Text("\(sensor.label) (\(sensor.key))").tag(sensor.key)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    let points = defaultPoints()
                    onCreate(FanCurve(name: name, fanIndices: fanSet.sorted(),
                                      sensorKey: sensorKey, points: points))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(fanMissing || sensorMissing)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            soldierDefaults()
        }
    }

    private var fanMissing: Bool { fanSet.isEmpty }
    private var sensorMissing: Bool { vm.sensors.first { $0.key == sensorKey } == nil }

    private func soldierDefaults() {
        fanSet = Set(vm.fans.map(\.index))
        if let cpu = vm.sensors.first(where: { $0.category == .cpu }) {
            sensorKey = cpu.key
        } else if let any = vm.sensors.first {
            sensorKey = any.key
        }
    }

    private func defaultPoints() -> [CurvePoint] {
        guard let fan = vm.fans.first(where: { fanSet.contains($0.index) }) else {
            return [CurvePoint(temperatureC: 35, rpm: 1200),
                    CurvePoint(temperatureC: 85, rpm: 6000)]
        }
        let low = (fan.minRPM + fan.actualRPM) / 2
        let high = fan.maxRPM
        return [
            CurvePoint(temperatureC: 35, rpm: Swift.max(low, 800)),
            CurvePoint(temperatureC: 55, rpm: (low + high) / 2),
            CurvePoint(temperatureC: 80, rpm: high),
        ]
    }
}

// MARK: - Interactive curve graph

/// Draggable temp→RPM graph. Drag a point to move it, click empty space to
/// add a point, ⌥-click a point to remove it. A live marker shows the
/// sensor's current temperature and its position on the curve.
struct CurveGraphView: View {
    let points: [CurvePoint]
    let fanMin: Double
    let fanMax: Double
    let currentTemp: Double?
    let computedRPM: Double?

    var onMove: (UUID, Double, Double) -> Void
    var onDelete: (UUID) -> Void

    @State private var draggingID: UUID?

    // Fixed axis ranges.
    private let tempRange = 20.0 ... 110.0

    var body: some View {
        GeometryReader { geo in
            let r = mapping(geo)
            ZStack {
                // Grid + axes
                grid(geo, r)

                // Curve line
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: r.point(first))
                    for pt in points.dropFirst() {
                        p.addLine(to: r.point(pt))
                    }
                }
                .stroke(Color.accentColor, lineWidth: 2)

                // Points
                ForEach(points) { pt in
                    Circle()
                        .fill(color(for: pt))
                        .frame(width: 12, height: 12)
                        .position(r.point(pt))
                        .overlay {
                            Text("\(Int(pt.temperatureC))° · \(Int(pt.rpm))")
                                .font(.caption2.monospacedDigit())
                                .offset(y: 18)
                                .position(r.point(pt))
                        }
                        .gesture(dragGesture(pt, r, geo))
                        .onTapGesture(count: 2) {
                            onDelete(pt.id)
                        }
                        .onLongPressGesture(minimumDuration: 1.0) {
                            onDelete(pt.id)
                        }
                }

                // Live temp marker
                if let t = currentTemp {
                    let x = r.x(t)
                    Rectangle()
                        .fill(Color.orange.opacity(0.8))
                        .frame(width: 1)
                        .offset(x: x)
                        .allowsHitTesting(false)

                    if let rpm = computedRPM {
                        Circle()
                            .stroke(Color.orange, lineWidth: 3)
                            .frame(width: 16, height: 16)
                            .position(x: x, y: r.y(rpm))
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .padding(.top, 24)
    }

    private func color(for pt: CurvePoint) -> Color {
        pt.id == draggingID ? .orange : .accentColor
    }

    private func mapping(_ geo: GeometryProxy) -> GeometryMap {
        GeometryMap(
            size: geo.size,
            tempRange: tempRange,
            rpmMin: fanMin,
            rpmMax: fanMax
        )
    }

    private func dragGesture(_ pt: CurvePoint, _ r: GeometryMap, _ geo: GeometryProxy) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if draggingID == nil { draggingID = pt.id }
                let temp = r.tempFromLocation(value.location.x)
                let rpm = r.rpmFromLocation(value.location.y)
                onMove(pt.id, temp, rpm)
            }
            .onEnded { _ in
                draggingID = nil
            }
    }

    /// Axis ruler labels.
    private func grid(_ geo: GeometryProxy, _ r: GeometryMap) -> some View {
        ZStack {
            // Horizontal gridlines every 20% fan range
            ForEach(0...4, id: \.self) { i in
                let fraction = Double(i) / 4.0
                let rpm = r.rpmRange.lowerBound + fraction * (r.rpmRange.upperBound - r.rpmRange.lowerBound)
                let y = r.y(rpm)
                Divider()
                    .overlay(Color.primary.opacity(0.1))
                    .offset(y: y - geo.size.height / 2)
                Text("\(Int(rpm))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .position(x: 12, y: y)
            }
            // Vertical gridlines every 20%
            ForEach(0...4, id: \.self) { i in
                let fraction = Double(i) / 4.0
                let temp = r.tempRange.lowerBound + fraction * (r.tempRange.upperBound - r.tempRange.lowerBound)
                let x = r.x(temp)
                Divider()
                    .overlay(Color.primary.opacity(0.1))
                    .offset(x: x - geo.size.width / 2)
                Text("\(Int(temp))°")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .position(x: x, y: geo.size.height - 10)
            }
        }
    }
}

/// Converts between temperature / RPM values and view coordinates.
private struct GeometryMap {
    let size: CGSize
    let tempRange: ClosedRange<Double>
    let rpmMin: Double
    let rpmMax: Double

    var paddingX: CGFloat = 40
    var paddingY: CGFloat = 24

    var rpmRange: ClosedRange<Double> {
        rpmMin < rpmMax ? rpmMin ... rpmMax : (rpmMin - 1) ... (rpmMax + 1)
    }

    private var width: CGFloat { Swift.max(size.width - paddingX * 2, 1) }
    private var height: CGFloat { Swift.max(size.height - paddingY * 2, 1) }

    func x(_ temp: Double) -> CGFloat {
        let t = (temp - tempRange.lowerBound) / (tempRange.upperBound - tempRange.lowerBound)
        return paddingX + CGFloat(t) * width
    }

    func y(_ rpm: Double) -> CGFloat {
        let span = rpmRange.upperBound - rpmRange.lowerBound
        let t = (rpm - rpmRange.lowerBound) / Swift.max(span, 1)
        return size.height - paddingY - CGFloat(t) * height
    }

    func point(_ pt: CurvePoint) -> CGPoint {
        CGPoint(x: x(pt.temperatureC), y: y(pt.rpm))
    }

    func tempFromLocation(_ xCoord: CGFloat) -> Double {
        let t = Double((xCoord - paddingX) / width)
        return tempRange.lowerBound + t * (tempRange.upperBound - tempRange.lowerBound)
    }

    func rpmFromLocation(_ yCoord: CGFloat) -> Double {
        let t = Double((size.height - paddingY - yCoord) / height)
        let span = rpmRange.upperBound - rpmRange.lowerBound
        return rpmRange.lowerBound + t * span
    }
}