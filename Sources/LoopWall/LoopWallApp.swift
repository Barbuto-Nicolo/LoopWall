import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon until a window opens
    }
}

@main
struct LoopWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra(AppConfig.appName, systemImage: "play.rectangle.fill") {
            MenuBarContent().environmentObject(state)
        }
        Window("\(AppConfig.appName) Library", id: "library") {
            LibraryView()
                .environmentObject(state)
                .frame(minWidth: 640, minHeight: 440)
        }
        .defaultLaunchBehavior(.suppressed)
        Window("\(AppConfig.appName) Settings", id: "settings") {
            SettingsView().environmentObject(state)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}
