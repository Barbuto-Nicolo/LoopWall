import Foundation

/// User-facing pause toggles, persisted in UserDefaults.
/// The Settings UI (Checkpoint 3) binds to these same keys.
enum PlaybackSettings {
    static let pauseWhenOccludedKey = "pauseWhenOccluded"
    static let pauseOnLowPowerKey = "pauseOnLowPower"
    static let pauseWhenScreenOffOrLockedKey = "pauseWhenScreenOffOrLocked"

    /// All rules are enabled by default.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            pauseWhenOccludedKey: true,
            pauseOnLowPowerKey: true,
            pauseWhenScreenOffOrLockedKey: true
        ])
    }

    static var pauseWhenOccluded: Bool { UserDefaults.standard.bool(forKey: pauseWhenOccludedKey) }
    static var pauseOnLowPower: Bool { UserDefaults.standard.bool(forKey: pauseOnLowPowerKey) }
    static var pauseWhenScreenOffOrLocked: Bool { UserDefaults.standard.bool(forKey: pauseWhenScreenOffOrLockedKey) }
}
