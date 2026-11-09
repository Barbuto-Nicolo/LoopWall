import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(state.isPaused ? "Resume" : "Pause") { state.togglePause() }
        Toggle("Mute", isOn: Binding(get: { state.isMuted }, set: { _ in state.toggleMute() }))
        Button("Next Wallpaper") { state.nextWallpaper() }
            .disabled(state.store.items.isEmpty)
        Divider()
        Button("Open Library…") { show("library") }
        Button("Settings…") { show("settings") }
        Divider()
        Button("Quit \(AppConfig.appName)") { NSApp.terminate(nil) }
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApp.activate()
    }
}
