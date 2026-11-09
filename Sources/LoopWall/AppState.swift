import AppKit
import Combine

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
}

/// Which display(s) a click in the library applies to.
enum DisplayTarget: Hashable {
    case all
    case display(CGDirectDisplayID)
}

/// Glue between the library, the wallpaper windows and the UI.
@MainActor
final class AppState: ObservableObject {
    let store = LibraryStore()
    let manager = WallpaperWindowManager()
    let steam = SteamImporter()

    @Published var isPaused = false
    @Published var isMuted = true
    @Published var errorMessage: String?
    @Published var target: DisplayTarget = .all
    @Published private(set) var displays: [DisplayInfo] = []

    private var cancellables: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []

    init() {
        PlaybackSettings.registerDefaults()
        manager.onError = { [weak self] message in self?.errorMessage = message }
        errorMessage = store.storageError

        // Re-publish store changes so views observing AppState refresh too.
        store.objectWillChange
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.objectWillChange.send() } }
            .store(in: &cancellables)

        refreshDisplays()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshDisplays() } })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.windowsChanged() } })

        restoreWallpapers()
    }

    // MARK: - Restore / apply

    /// Re-applies the last wallpaper per display (also for displays connected later).
    private func restoreWallpapers() {
        for (key, itemID) in store.assignments {
            if let id = CGDirectDisplayID(key), let item = store.item(withID: itemID) {
                manager.setVideo(store.videoURL(for: item), for: id)
            }
        }
        if let item = store.item(withID: store.defaultItemID) {
            manager.setDefaultVideo(store.videoURL(for: item))
        }
    }

    func apply(_ item: LibraryItem) {
        let url = store.videoURL(for: item)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "The video file for \"\(item.name)\" is missing from the library."
            return
        }
        switch target {
        case .all:
            for display in displays {
                store.assign(item, to: display.id)
                manager.setVideo(url, for: display.id)
            }
            store.setDefault(item)
            manager.setDefaultVideo(url)
        case .display(let id):
            store.assign(item, to: id)
            manager.setVideo(url, for: id)
        }
    }

    /// Moves every display to the next library item (wrapping around).
    func nextWallpaper() {
        let items = store.items
        guard !items.isEmpty else { return }
        for display in displays {
            let current = store.assignedItem(for: display.id)
            let index = current.flatMap { current in items.firstIndex { $0.id == current.id } }
            let next = items[((index ?? -1) + 1) % items.count]
            store.assign(next, to: display.id)
            manager.setVideo(store.videoURL(for: next), for: display.id)
        }
    }

    func importVideos(_ urls: [URL]) async {
        let errors = await store.importVideos(urls)
        if !errors.isEmpty { errorMessage = errors.joined(separator: "\n") }
    }

    func remove(_ item: LibraryItem) {
        manager.removeVideo(store.videoURL(for: item))
        store.remove(item)
        if let message = store.storageError { errorMessage = message }
    }

    // MARK: - Menu bar actions

    func togglePause() {
        isPaused.toggle()
        manager.setUserPaused(isPaused)
    }

    func toggleMute() {
        isMuted.toggle()
        manager.setMuted(isMuted)
    }

    // MARK: - Displays and Dock icon

    private func refreshDisplays() {
        displays = NSScreen.screens.enumerated().compactMap { index, screen in
            screen.displayID.map { DisplayInfo(id: $0, name: "\(index + 1). \(screen.localizedName)") }
        }
        if case .display(let id) = target, !displays.contains(where: { $0.id == id }) { target = .all }
    }

    /// Shows the Dock icon only while a regular (titled) window, such as the library, is open.
    func windowsChanged() {
        DispatchQueue.main.async {
            let hasWindow = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
            NSApp.setActivationPolicy(hasWindow ? .regular : .accessory)
            if hasWindow { NSApp.activate() }
        }
    }
}
