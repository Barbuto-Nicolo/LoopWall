import AppKit
import IOKit.ps

/// Why a wallpaper is currently paused. A wallpaper plays only when no reason is active.
enum PauseReason: Hashable {
    case occluded
    case lowPower
    case screenOffOrLocked
    case user          // paused from the menu bar
}

/// Tracks system-wide conditions (Low Power Mode on battery, screen sleep, lock)
/// and reports which global pause reasons are active, honouring the user's toggles.
/// Per-window occlusion is handled by WallpaperWindowManager.
@MainActor
final class PlaybackPolicy {
    /// Called whenever the set of active reasons may have changed.
    var onChange: (() -> Void)?

    private var screenAsleep = false
    private var locked = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenAsleep = true; self?.onChange?() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenAsleep = false; self?.onChange?() }
        })
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.locked = true; self?.onChange?() }
        })
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.locked = false; self?.onChange?() }
        })
        // Low Power Mode toggled.
        observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        })
        // User toggled a setting.
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        })
        // Power source switched between AC and battery.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let policy = Unmanaged<PlaybackPolicy>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { policy.onChange?() }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    /// Global reasons that should currently pause playback.
    func activeReasons() -> Set<PauseReason> {
        var reasons: Set<PauseReason> = []
        if PlaybackSettings.pauseOnLowPower,
           ProcessInfo.processInfo.isLowPowerModeEnabled,
           Self.isOnBattery() {
            reasons.insert(.lowPower)
        }
        if PlaybackSettings.pauseWhenScreenOffOrLocked, screenAsleep || locked {
            reasons.insert(.screenOffOrLocked)
        }
        return reasons
    }

    private static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else {
            return false
        }
        return (type as String) == kIOPSBatteryPowerValue
    }
}
