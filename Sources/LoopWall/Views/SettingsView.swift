import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage(PlaybackSettings.pauseWhenOccludedKey) private var pauseWhenOccluded = true
    @AppStorage(PlaybackSettings.pauseOnLowPowerKey) private var pauseOnLowPower = true
    @AppStorage(PlaybackSettings.pauseWhenScreenOffOrLockedKey) private var pauseWhenScreenOffOrLocked = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Pause playback") {
                Toggle("When the wallpaper is fully covered (e.g. fullscreen app)", isOn: $pauseWhenOccluded)
                Toggle("On battery with Low Power Mode", isOn: $pauseOnLowPower)
                Toggle("When the screen is asleep or locked", isOn: $pauseWhenScreenOffOrLocked)
            }
            Section("General") {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let loginError {
                    Text("Launch at login failed: \(loginError)")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    /// Registers or unregisters the app as a login item; failures are shown, not worked around.
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = enabled
            loginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = error.localizedDescription
        }
    }
}
