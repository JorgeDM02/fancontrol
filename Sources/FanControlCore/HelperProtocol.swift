import Foundation

/// Shared identifiers for the privileged helper daemon.
public enum FanControlConstants {
    /// The mach service name bound by the LaunchDaemon. Must match
    /// both the LaunchDaemon plist `MachServices` entry and the app's
    /// NSXPCConnection.
    public static let machServiceName = "com.fancontrol.helper"

    /// Plist label (also the filename stem).
    public static let launchdLabel = "com.fancontrol.helper"

    /// Filesystem paths used by the installer.
    public static let helperBinaryPath  = "/Library/PrivilegedHelperTools/\(launchdLabel)"
    public static let launchdPlistPath  = "/Library/LaunchDaemons/\(launchdLabel).plist"

    /// Reconciliation loop interval. Empirically thermalmonitord clobbers
    /// F0Tg every ~1400 ms, so 300 ms gives us ~4 wins per clobber cycle,
    /// which is enough to hold a custom target.
    public static let reconciliationInterval: TimeInterval = 0.3

    /// If the client stops sending heartbeats for this long, the daemon
    /// returns all fans to auto mode as a safety watchdog.
    public static let watchdogTimeout: TimeInterval = 10.0

    /// App-side curve refresh rate. The app evaluates active curves about
    /// once a second and pushes targets through the helper.
    public static let curveTickInterval: TimeInterval = 1.0
}

/// The XPC interface between the SwiftUI app (client) and the privileged
/// helper daemon (server). Keep the surface small.
@objc public protocol FanHelperProtocol {

    /// Identify the helper. Used as a liveness/version check.
    func helperVersion(reply: @escaping @Sendable (String) -> Void)

    /// Client tells the helper "I'm still here" so the watchdog doesn't
    /// revert overrides.
    func heartbeat(reply: @escaping @Sendable (Bool) -> Void)

    /// Put a fan into manual mode and hold `rpm` against clobbers.
    /// The helper takes over the reconciliation loop for this fan.
    func setFanOverride(index: Int, rpm: Double,
                        reply: @escaping @Sendable (Bool, String) -> Void)

    /// Put a fan at its maximum RPM (reads F0Mx at call time).
    func setFanFullSpeed(index: Int,
                         reply: @escaping @Sendable (Bool, String) -> Void)

    /// Write mode=0 for the fan and stop the reconciliation loop.
    func setFanAuto(index: Int,
                    reply: @escaping @Sendable (Bool, String) -> Void)

    /// Return the current override status per fan, so the app can
    /// reconcile its UI with daemon state across reconnects.
    func overrideStatus(reply: @escaping @Sendable ([FanOverrideState]) -> Void)
}

/// Per-fan override state maintained by the helper.
@objc(FanOverrideState)
public final class FanOverrideState: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    @objc public let index: Int
    @objc public let mode: OverrideMode
    @objc public let targetRPM: Double

    public init(index: Int, mode: OverrideMode, targetRPM: Double) {
        self.index = index
        self.mode = mode
        self.targetRPM = targetRPM
    }

    public func encode(with coder: NSCoder) {
        coder.encode(index, forKey: "index")
        coder.encode(mode.rawValue, forKey: "mode")
        coder.encode(targetRPM, forKey: "targetRPM")
    }

    public required init?(coder: NSCoder) {
        self.index = coder.decodeInteger(forKey: "index")
        let modeRaw = coder.decodeInteger(forKey: "mode")
        self.mode = OverrideMode(rawValue: modeRaw) ?? .auto
        self.targetRPM = coder.decodeDouble(forKey: "targetRPM")
    }
}

@objc public enum OverrideMode: Int, Sendable {
    /// Helper is not actively writing this fan.
    case auto = 0
    /// Helper is holding a custom RPM target via the reconciliation loop.
    case custom = 1
    /// Helper pushed fan to F0Mx; no loop needed.
    case fullSpeed = 2
}