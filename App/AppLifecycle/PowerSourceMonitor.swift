import Foundation
import IOKit.ps
import OSLog
import PowerAssertions

/// Reads the battery level / power adapter state from IOKit power sources
/// and calls back on every change. Event-driven (`IOPSNotificationCreateRunLoopSource`),
/// no polling. On a Mac without a battery it reports `.desktop` and the
/// battery guard never fires.
@MainActor
final class PowerSourceMonitor {
    static let shared = PowerSourceMonitor()

    private var runLoopSource: CFRunLoopSource?
    private var onChange: ((PowerSourceSnapshot) -> Void)?

    private init() {}

    func start(onChange: @escaping (PowerSourceSnapshot) -> Void) {
        self.onChange = onChange
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.onChange?(PowerSourceMonitor.snapshot()) }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    static func snapshot() -> PowerSourceSnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return .desktop }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let onAC = providing != kIOPSBatteryPowerValue
        let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  desc[kIOPSIsPresentKey] as? Bool ?? true
            else { continue }
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            return PowerSourceSnapshot(hasBattery: true, batteryPercent: percent, onACPower: onAC)
        }
        return .desktop
    }
}
