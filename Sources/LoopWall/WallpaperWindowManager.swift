import AppKit

extension NSScreen {
    /// Stable identifier of the physical display.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// Keeps one borderless desktop-level window per connected display,
/// each hosting its own video, and reacts to display changes and pause rules.
@MainActor
final class WallpaperWindowManager {
    private struct Entry {
        let window: NSWindow
        let controller: PlaybackController
        let url: URL
    }

    private var entries: [CGDirectDisplayID: Entry] = [:]
    private var assigned: [CGDirectDisplayID: URL] = [:]   // video chosen per display
    private var defaultURL: URL?                           // used for displays without a choice
    private var loading: Set<CGDirectDisplayID> = []
    private let policy = PlaybackPolicy()
    private var observers: [NSObjectProtocol] = []
    private var userPaused = false
    private(set) var isMuted = true

    /// Called with a user-readable message when a wallpaper cannot be shown.
    var onError: ((String) -> Void)?

    init() {
        policy.onChange = { [weak self] in self?.applyPauseRules() }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPauseRules() }
        })
    }

    /// Video used for any display that has no explicit assignment (also newly connected ones).
    func setDefaultVideo(_ url: URL) {
        defaultURL = url
        reconcile()
    }

    /// Assigns a video to one display.
    func setVideo(_ url: URL, for displayID: CGDirectDisplayID) {
        assigned[displayID] = url
        reconcile()
    }

    /// Pause/resume requested by the user (menu bar).
    func setUserPaused(_ paused: Bool) {
        userPaused = paused
        applyPauseRules()
    }

    /// Mutes or unmutes every wallpaper (muted by default).
    func setMuted(_ muted: Bool) {
        isMuted = muted
        for entry in entries.values { entry.controller.setMuted(muted) }
    }

    /// Forgets a video everywhere it is used (assignments, default, running windows).
    func removeVideo(_ url: URL) {
        assigned = assigned.filter { $0.value != url }
        if defaultURL == url { defaultURL = nil }
        for (id, entry) in entries where entry.url == url { removeEntry(for: id) }
    }

    /// Brings windows in line with the connected displays: adds, removes, resizes, swaps videos.
    func reconcile() {
        let screens = NSScreen.screens.compactMap { screen in screen.displayID.map { ($0, screen) } }
        let connected = Set(screens.map { $0.0 })

        // Tear down windows of displays that disappeared.
        for id in entries.keys where !connected.contains(id) {
            removeEntry(for: id)
        }

        for (id, screen) in screens {
            guard let url = assigned[id] ?? defaultURL else { continue }
            if let entry = entries[id] {
                if entry.url == url {
                    entry.window.setFrame(screen.frame, display: true)   // resolution/arrangement change
                } else {
                    createEntry(id: id, url: url)   // the old window is swapped out once the new one is ready
                }
            } else {
                createEntry(id: id, url: url)
            }
        }
    }

    private func removeEntry(for id: CGDirectDisplayID) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.controller.stop()
        entry.window.orderOut(nil)
        entry.window.close()
    }

    private func createEntry(id: CGDirectDisplayID, url: URL) {
        guard !loading.contains(id) else { return }
        loading.insert(id)
        Task {
            var loaded: PlaybackController?
            do {
                loaded = try await PlaybackController(url: url)
            } catch {
                onError?("Display \(id): \(error.localizedDescription)")
            }
            loading.remove(id)
            // The display may have been unplugged while the file was loading.
            guard let controller = loaded,
                  let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { return }
            controller.setMuted(isMuted)
            let window = makeWindow(on: screen, layer: controller.layer)
            let old = entries[id]
            entries[id] = Entry(window: window, controller: controller, url: url)
            window.orderFrontRegardless()
            if let old {
                old.controller.stop()
                old.window.orderOut(nil)
                old.window.close()
            }
            applyPauseRules()
            reconcile()   // the desired video may have changed while this one was loading
        }
    }

    private func makeWindow(on screen: NSScreen, layer: CALayer) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame,
                              styleMask: .borderless,
                              backing: .buffered,
                              defer: false,
                              screen: screen)
        // Desktop window level: below Finder icons and all normal windows.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false

        let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        content.wantsLayer = true
        layer.frame = content.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        content.layer?.addSublayer(layer)
        window.contentView = content
        window.setFrame(screen.frame, display: true)
        return window
    }

    /// Re-evaluates every pause rule for every display.
    private func applyPauseRules() {
        let global = policy.activeReasons()
        for entry in entries.values {
            entry.controller.setPaused(.lowPower, global.contains(.lowPower))
            entry.controller.setPaused(.screenOffOrLocked, global.contains(.screenOffOrLocked))
            let occluded = !entry.window.occlusionState.contains(.visible)
            entry.controller.setPaused(.user, userPaused)
            entry.controller.setPaused(.occluded, PlaybackSettings.pauseWhenOccluded && occluded)
        }
    }
}
