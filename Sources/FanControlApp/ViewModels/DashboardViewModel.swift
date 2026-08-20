import Foundation
import FanControlCore

/// What the app *wants* each fan to do. Combined with enabled curves to
/// produce the actual commands pushed to the helper daemon.
enum FanControlIntent: Equatable {
    case auto
    case custom(Double)
    case fullSpeed
    case curve(UUID)
}

/// The push loop coalesces repeated intent changes (e.g. slider drags) by
/// only re-sending when the effective target actually changed.
private struct PushedTarget: Equatable {
    var key: String   // discriminator of intent shape
    var rpm: Int
}

/// Owns monitoring, per-fan control intents, curve evaluation, presets,
/// and the connection to the privileged helper.
@MainActor
final class DashboardViewModel: ObservableObject {

    // MARK: Published state

    @Published private(set) var fans: [FanReading] = []
    @Published private(set) var sensors: [SensorReading] = []
    @Published private(set) var cpuTemp: Double?
    @Published private(set) var cpuTempLabel: String?
    @Published private(set) var helperStatus: HelperInstallStatus = .unknown
    @Published private(set) var isTakingControl = false
    @Published private(set) var engagedCurveIDs: Set<UUID> = []
    @Published var lastMessage: String?

    var sensorReader = SensorReader()

    // MARK: Dependencies

    let client = HelperClient()
    let presetStore = PresetStore()
    let curveStore = CurveStore()

    private let installer: HelperInstaller
    private let smc = SMC.shared
    private let fanReader = FanReader()

    // MARK: Internals

    private var intents: [Int: FanControlIntent] = [:]
    private var pushed: [Int: PushedTarget] = [:]
    private var helperOverrides: [Int: FanOverrideState] = [:]
    private var curveActive: Set<UUID> = []
    private var helperEngaged = false

    private var monitorTimer: DispatchSourceTimer?
    private var controlTimer: DispatchSourceTimer?
    private var heartbeatTimer: DispatchSourceTimer?
    private var running = false

    init() {
        self.installer = HelperInstaller(client: client)
    }

    var hasFans: Bool { !fans.isEmpty }

    // MARK: - Lifecycle

    func start() {
        guard !running else { return }
        running = true
        do { try smc.open() } catch { post(lastMessage: "SMC open failed: \(error)") }

        sensorReader = SensorReader()

        startTimers()
        Task { await refreshHelperStatus() }
        Task { await refreshNow() }
    }

    func stop() {
        running = false
        monitorTimer?.cancel(); monitorTimer = nil
        controlTimer?.cancel(); controlTimer = nil
        heartbeatTimer?.cancel(); heartbeatTimer = nil
        smc.close()
    }

    /// Quit path: try to hand every fan back to the system, wait briefly,
    /// then stop. The helper's watchdog is the backstop if this times out.
    func shutdown() async {
        stop()
        guard helperEngaged else { return }
        let indices = Array(Set(engagedFanIndices()))
        for index in indices {
            _ = await client.setFanAuto(index: index)
        }
    }

    func engagedFanIndices() -> [Int] {
        var set = Set<Int>()
        for (index, intent) in intents {
            switch intent {
            case .auto: break
            case .custom, .fullSpeed, .curve: set.insert(index)
            }
        }
        return Array(set)
    }

    func intent(for index: Int) -> FanControlIntent {
        intents[index] ?? .auto
    }

    /// Human-readable summary of the current per-fan intents (for the save sheet).
    func presetPreamble() -> String {
        let parts = fans.map { fan -> String in
            switch intents[fan.index] ?? .auto {
            case .auto:      return "Fan \(fan.index): system (auto)"
            case .custom(let rpm): return "Fan \(fan.index): \(Int(rpm)) rpm"
            case .fullSpeed: return "Fan \(fan.index): full speed"
            case .curve(let uuid):
                let name = curveStore.curves.first { $0.id == uuid }?.name ?? "curve"
                return "Fan \(fan.index): curve “\(name)” (saved as auto)"
            }
        }
        return parts.joined(separator: "\n")
    }

    func currentTarget(for index: Int, fallback: Double) -> Double {
        switch intents[index] {
        case .custom(let rpm): return rpm
        case .fullSpeed:       return fallback
        default:               return fallback
        }
    }

    // MARK: - Timers

    private func startTimers() {
        // Main-queue timers: creating `Task {}` here inherits the main actor,
        // avoiding a Swift-concurrency trap when hopping from a background
        // thread into @MainActor methods. SMC reads are millisecond-fast so
        // the main thread is plenty.
        let monitor = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        monitor.schedule(deadline: .now() + 0.5, repeating: 2.0, leeway: .milliseconds(200))
        monitor.setEventHandler { [weak self] in
            Task { [weak self] in await self?.refreshNow() }
        }
        monitor.resume()
        self.monitorTimer = monitor

        let control = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        control.schedule(deadline: .now() + 1.0, repeating: 0.4, leeway: .milliseconds(50))
        control.setEventHandler { [weak self] in
            Task { [weak self] in await self?.applyIntents() }
        }
        control.resume()
        self.controlTimer = control

        let hb = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        hb.schedule(deadline: .now() + 2.0, repeating: 2.0, leeway: .milliseconds(100))
        hb.setEventHandler { [weak self] in
            Task { [weak self] in await self?.heartbeat() }
        }
        hb.resume()
        self.heartbeatTimer = hb
    }

    private func heartbeat() async {
        guard helperEngaged else { return }
        _ = await client.heartbeat()
    }

    // MARK: - Monitoring

    private func refreshNow() async {
        let fanReadings = fanReader.readAll()
        var sensorReadings: [SensorReading] = []
        sensorReadings = sensorReader.readAll()
        let cpu = sensorReader.cpuTemperature(from: sensorReadings)
        let cpuLabel = sensorReadings.first { $0.category == .cpu }?.label

        fans = fanReadings
        sensors = sensorReadings
        cpuTemp = cpu
        cpuTempLabel = cpuLabel
    }

    func refreshNowSync() {
        // For tests / debugging; not used on the hot path.
        fans = fanReader.readAll()
        sensors = sensorReader.readAll()
        cpuTemp = sensorReader.cpuTemperature(from: sensors)
    }

    // MARK: - Helper install

    func refreshHelperStatus() async {
        let status = await installer.status()
        helperStatus = status
    }

    func installHelper() async {
        do {
            try await installer.install()
            helperStatus = .running(version: "installed")
            client.reset()
            _ = await client.ping(timeout: 3.0)
            await refreshHelperStatus()
            post(lastMessage: "Helper installed.")
        } catch {
            post(lastMessage: "Helper install failed: \(error.localizedDescription)")
        }
    }

    func uninstallHelper() async {
        do {
            shutdownControl()
            try await installer.uninstall()
            helperStatus = .notInstalled
            post(lastMessage: "Helper removed.")
        } catch {
            post(lastMessage: "Helper removal failed: \(error.localizedDescription)")
        }
    }

    func takeControl() async {
        await refreshHelperStatus()
        guard helperStatus.isRunning else { return }
        helperEngaged = true
        isTakingControl = true
        // Push whatever the UI already desires.
        await applyIntents()
        post(lastMessage: "Fan control engaged (auto-reverts on quit or crash).")
    }

    private func releaseControl() {
        helperEngaged = false
        isTakingControl = false
    }

    func releaseControlFromUI() {
        releaseControl()
        for index in engagedFanIndices() {
            Task { _ = await client.setFanAuto(index: index) }
        }
        pushed.removeAll()
        curveActive.removeAll()
        engagedCurveIDs = []
        post(lastMessage: "Control released — fans are back to auto.")
    }

    // MARK: - Intent mutations (from UI)

    func setFanAuto(_ index: Int) {
        intents[index] = .auto
        disengageCurves(onFan: index)
        pushed.removeValue(forKey: index)
    }

    func setFanCustom(_ index: Int, rpm: Double) {
        intents[index] = .custom(rpm)
        disengageCurves(onFan: index)
    }

    func setFanFullSpeed(_ index: Int) {
        intents[index] = .fullSpeed
        disengageCurves(onFan: index)
    }

    func engageCurve(_ curve: FanCurve) {
        // Turn off any other intent/curve on the fans this curve targets.
        for f in curve.fanIndices {
            intents[f] = .curve(curve.id)
        }
        for other in curveStore.curves
        where other.id != curve.id && other.isEnabled
            && other.fanIndices.contains(where: curve.fanIndices.contains) {
            var copy = other
            copy.isEnabled = false
            curveStore.update(copy)
            curveActive.remove(other.id)
        }
        var copy = curve
        copy.isEnabled = true
        curveStore.update(copy)
        for f in curve.fanIndices {
            pushed.removeValue(forKey: f)
        }
        engagedCurveIDs = curveActive
    }

    func disengageCurve(_ curve: FanCurve) {
        for f in curve.fanIndices where intents[f] == .curve(curve.id) {
            intents[f] = .auto
        }
        var copy = curve
        copy.isEnabled = false
        curveStore.update(copy)
        curveActive.remove(curve.id)
        engagedCurveIDs = curveActive
        for f in curve.fanIndices {
            pushed.removeValue(forKey: f)
        }
    }

    /// Delete a curve from storage, releasing any fans it was controlling.
    func deleteCurve(_ curve: FanCurve) {
        disengageCurve(curve)
        curveStore.delete(curve)
        post(lastMessage: "Deleted curve “\(curve.name)”.")
    }

    /// Disengage every curve assigned to a given fan (used when manual control takes over).
    private func disengageCurves(onFan index: Int) {
        for curve in curveStore.curves where curve.targets(index) && curve.isEnabled {
            var copy = curve
            copy.isEnabled = false
            curveStore.update(copy)
            curveActive.remove(curve.id)
        }
        engagedCurveIDs = curveActive
    }

    // MARK: - Presets

    func saveCurrentAsPreset(named name: String) {
        var settings: [FanSetting] = []
        for (index, intent) in intents {
            switch intent {
            case .auto:
                settings.append(FanSetting(fanIndex: index, mode: .auto, rpm: 0))
            case .custom(let rpm):
                settings.append(FanSetting(fanIndex: index, mode: .custom, rpm: rpm))
            case .fullSpeed:
                settings.append(FanSetting(fanIndex: index, mode: .fullSpeed, rpm: 0))
            case .curve:
                // Curves aren't captured in presets; record as auto.
                settings.append(FanSetting(fanIndex: index, mode: .auto, rpm: 0))
            }
        }
        // Include fans we have readings for even if untouched, as auto.
        for fan in fans where settings.first(where: { $0.fanIndex == fan.index }) == nil {
            settings.append(FanSetting(fanIndex: fan.index, mode: .auto, rpm: 0))
        }
        settings.sort { $0.fanIndex < $1.fanIndex }
        _ = presetStore.add(name: name, settings: settings)
        post(lastMessage: "Saved preset “\(name)”.")
    }

    func applyPreset(_ preset: FanPreset) {
        shutdownControl()
        for setting in preset.settings {
            switch setting.mode {
            case .auto:     intents[setting.fanIndex] = .auto
            case .custom:   intents[setting.fanIndex] = .custom(setting.rpm)
            case .fullSpeed:intents[setting.fanIndex] = .fullSpeed
            }
            disengageCurves(onFan: setting.fanIndex)
        }
        engagedCurveIDs = curveActive
        post(lastMessage: "Applied preset “\(preset.name)”.")
    }

    // MARK: - Control loop

    private func applyIntents() async {
        guard isTakingControl && helperEngaged else { return }

        let overrides = await client.overrideStatus()
        helperOverrides = Dictionary(uniqueKeysWithValues: overrides.map { ($0.index, $0) })

        for index in engagedFanIndices() {
            guard let intent = intents[index], intent != .auto else { continue }
            await applyIntent(fanIndex: index, intent: intent)
        }

        // Release any fan the helper still holds but the app no longer wants.
        for state in overrides where intents[state.index] == nil || intents[state.index] == .auto {
            _ = await client.setFanAuto(index: state.index)
            pushed.removeValue(forKey: state.index)
        }
    }

    private func applyIntent(fanIndex: Int, intent: FanControlIntent) async {
        switch intent {
        case .auto:
            _ = await client.setFanAuto(index: fanIndex)
            pushed.removeValue(forKey: fanIndex)

        case .custom(let rpm):
            let key = "custom"
            let target = Int(rpm.rounded())
            guard pushed[fanIndex] != PushedTarget(key: key, rpm: target) else { return }
            let (ok, message) = await client.setFanOverride(index: fanIndex, rpm: Double(target))
            if ok {
                pushed[fanIndex] = PushedTarget(key: key, rpm: target)
            } else {
                post(lastMessage: "set fan \(fanIndex): \(message)")
            }

        case .fullSpeed:
            let key = "full"
            guard pushed[fanIndex] != PushedTarget(key: key, rpm: -1) else { return }
            let (ok, message) = await client.setFanFullSpeed(index: fanIndex)
            if ok {
                pushed[fanIndex] = PushedTarget(key: key, rpm: -1)
            } else {
                post(lastMessage: "set fan \(fanIndex): \(message)")
            }

        case .curve(let uuid):
            guard let curve = curveStore.curves.first(where: { $0.id == uuid }) else { return }
            let temp = sensorValue(for: curve.sensorKey)
            let fan = fans.first { $0.index == fanIndex }

            // Sensor or fan disappeared — never leave the fan pinned; release to auto.
            guard let t = temp, let fan else {
                if curveActive.contains(uuid) {
                    curveActive.remove(uuid)
                    engagedCurveIDs = curveActive
                }
                let key = "curve-off"
                guard pushed[fanIndex] != PushedTarget(key: key, rpm: -2) else { return }
                let (ok, _) = await client.setFanAuto(index: fanIndex)
                if ok {
                    pushed[fanIndex] = PushedTarget(key: key, rpm: -2)
                }
                return
            }

            let currentlyActive = curveActive.contains(uuid)
            if let rpm = CurveEvaluator.evaluate(
                curve: curve,
                temperature: t,
                minRPM: fan.minRPM,
                maxRPM: fan.maxRPM,
                currentlyActive: currentlyActive
            ) {
                if !curveActive.contains(uuid) {
                    curveActive.insert(uuid)
                    engagedCurveIDs = curveActive
                }
                let target = Int(rpm.rounded())
                guard pushed[fanIndex] != PushedTarget(key: "curve-\(uuid)", rpm: target) else { return }
                let (ok, message) = await client.setFanOverride(index: fanIndex, rpm: Double(target))
                if ok {
                    pushed[fanIndex] = PushedTarget(key: "curve-\(uuid)", rpm: target)
                } else {
                    post(lastMessage: "set fan \(fanIndex) (curve): \(message)")
                }
            } else {
                if curveActive.contains(uuid) {
                    curveActive.remove(uuid)
                    engagedCurveIDs = curveActive
                }
                let key = "curve-off"
                guard pushed[fanIndex] != PushedTarget(key: key, rpm: -2) else { return }
                let (ok, _) = await client.setFanAuto(index: fanIndex)
                if ok {
                    pushed[fanIndex] = PushedTarget(key: key, rpm: -2)
                }
            }
        }
    }

    private func sensorValue(for key: String) -> Double? {
        sensors.first { $0.key == key }?.celsius
    }

    /// Called when taking control is explicitly revoked or helper removed.
    private func shutdownControl() {
        isTakingControl = false
        helperEngaged = false
        pushed.removeAll()
        curveActive.removeAll()
        engagedCurveIDs = []
    }

    // MARK: - Misc

    private func post(lastMessage: String?) {
        self.lastMessage = lastMessage
    }
}