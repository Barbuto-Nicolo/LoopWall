import AVFoundation
import AppKit

struct LibraryItem: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    let fileName: String      // file inside the library's Videos folder
    let addedAt: Date
}

/// Stores imported videos, per-display assignments and thumbnails in
/// ~/Library/Application Support/<app name>/.
@MainActor
final class LibraryStore: ObservableObject {
    private struct Persisted: Codable {
        var items: [LibraryItem]
        var assignments: [String: UUID]   // display ID (as string) -> item
        var defaultItemID: UUID?
    }

    static let allowedExtensions: Set<String> = ["mp4", "mov", "m4v"]

    @Published private(set) var items: [LibraryItem] = []
    @Published private(set) var assignments: [String: UUID] = [:]
    @Published private(set) var defaultItemID: UUID?
    /// Set when the library could not be loaded or saved; shown in the UI.
    @Published var storageError: String?

    private let rootURL: URL
    private let videosURL: URL
    private let thumbnailsURL: URL
    private var stateURL: URL { rootURL.appendingPathComponent("library.json") }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        rootURL = support.appendingPathComponent(AppConfig.appName, isDirectory: true)
        videosURL = rootURL.appendingPathComponent("Videos", isDirectory: true)
        thumbnailsURL = rootURL.appendingPathComponent("Thumbnails", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: videosURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: stateURL.path) {
                let persisted = try JSONDecoder().decode(Persisted.self, from: Data(contentsOf: stateURL))
                items = persisted.items
                assignments = persisted.assignments
                defaultItemID = persisted.defaultItemID
            }
        } catch {
            storageError = "Could not load the library: \(error.localizedDescription)"
        }
    }

    func videoURL(for item: LibraryItem) -> URL { videosURL.appendingPathComponent(item.fileName) }
    private func thumbnailURL(for item: LibraryItem) -> URL { thumbnailsURL.appendingPathComponent("\(item.id.uuidString).jpg") }
    func item(withID id: UUID?) -> LibraryItem? { id.flatMap { id in items.first { $0.id == id } } }

    // MARK: - Assignments

    func assignedItem(for displayID: CGDirectDisplayID) -> LibraryItem? {
        item(withID: assignments[String(displayID)] ?? defaultItemID)
    }

    func assign(_ item: LibraryItem, to displayID: CGDirectDisplayID) {
        assignments[String(displayID)] = item.id
        save()
    }

    func setDefault(_ item: LibraryItem) {
        defaultItemID = item.id
        save()
    }

    // MARK: - Import / remove

    /// Copies the files into the library (off the main thread) and returns error messages, if any.
    /// `names` optionally overrides the display name per source URL (e.g. a Workshop title).
    func importVideos(_ urls: [URL], names: [URL: String] = [:]) async -> [String] {
        var errors: [String] = []
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard Self.allowedExtensions.contains(ext) else {
                errors.append("\(url.lastPathComponent): unsupported type (only .mp4, .mov, .m4v).")
                continue
            }
            let id = UUID()
            let fileName = "\(id.uuidString).\(ext)"
            let destination = videosURL.appendingPathComponent(fileName)
            do {
                try await Task.detached { try FileManager.default.copyItem(at: url, to: destination) }.value
                guard try await AVURLAsset(url: destination).load(.isPlayable) else {
                    try? FileManager.default.removeItem(at: destination)
                    errors.append("\(url.lastPathComponent): AVFoundation cannot play this file.")
                    continue
                }
                let name = names[url].flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingPathExtension().lastPathComponent
                items.append(LibraryItem(id: id, name: name,
                                         fileName: fileName, addedAt: Date()))
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        save()
        return errors
    }

    /// Removes an item and its copied video and thumbnail from the library folder.
    func remove(_ item: LibraryItem) {
        items.removeAll { $0.id == item.id }
        assignments = assignments.filter { $0.value != item.id }
        if defaultItemID == item.id { defaultItemID = nil }
        for url in [videoURL(for: item), thumbnailURL(for: item)] where FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.removeItem(at: url) }
            catch { storageError = "Could not delete \(url.lastPathComponent): \(error.localizedDescription)" }
        }
        save()
    }

    // MARK: - Thumbnails

    /// JPEG data for the item's thumbnail; generated once with AVAssetImageGenerator, then cached on disk.
    func thumbnailData(for item: LibraryItem) async -> Data? {
        let video = videoURL(for: item)
        let cache = thumbnailURL(for: item)
        return await Task.detached(priority: .utility) { () -> Data? in
            if let cached = try? Data(contentsOf: cache) { return cached }
            let asset = AVURLAsset(url: video)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 360)
            guard let duration = try? await asset.load(.duration),
                  let result = try? await generator.image(at: CMTime(seconds: min(1, duration.seconds / 2), preferredTimescale: 600)),
                  let jpeg = NSBitmapImageRep(cgImage: result.image)
                    .representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
            try? jpeg.write(to: cache, options: .atomic)
            return jpeg
        }.value
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(Persisted(items: items, assignments: assignments, defaultItemID: defaultItemID))
            try data.write(to: stateURL, options: .atomic)
        } catch {
            storageError = "Could not save the library: \(error.localizedDescription)"
        }
    }
}
