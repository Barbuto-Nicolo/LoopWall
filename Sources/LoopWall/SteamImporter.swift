import AppKit

/// A Workshop item folder whose project.json describes a video file.
struct WorkshopItem: Identifiable, Hashable {
    let id: String          // folder name (the Workshop ID)
    let title: String
    let videoURL: URL
}

struct UnsupportedItem: Identifiable, Hashable {
    let id: String
    let title: String
    let reason: String
}

struct WorkshopScan {
    var importable: [WorkshopItem] = []        // mp4/mov/m4v
    var needsConversion: [WorkshopItem] = []   // video type, but a format AVFoundation cannot play
    var unsupported: [UnsupportedItem] = []    // scene/web/application, broken entries, .pkg
}

/// Scans Wallpaper Engine Workshop folders, imports video items, and offers the optional
/// SteamCMD download and ffmpeg conversion helpers. It never handles Steam credentials:
/// the password and Steam Guard code are typed by the user in a Terminal window.
@MainActor
final class SteamImporter: ObservableObject {
    static let appID = "431960"
    private nonisolated static let playableExtensions: Set<String> = ["mp4", "mov", "m4v"]

    @Published private(set) var scan: WorkshopScan?
    @Published private(set) var isScanning = false
    @Published private(set) var busyItemID: String?
    @Published private(set) var importedIDs: Set<String> = []
    @Published private(set) var steamcmdPath: String?
    @Published private(set) var ffmpegPath: String?
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    /// Default place where Steam stores Wallpaper Engine Workshop items on macOS.
    static var suggestedFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/steamapps/workshop/content/\(appID)")
    }

    // MARK: - Folder scan

    /// Lets the user pick a folder (starting at the suggested one) and scans it.
    func chooseFolderAndScan() async {
        let panel = NSOpenPanel()
        panel.title = "Choose a Workshop content folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if FileManager.default.fileExists(atPath: Self.suggestedFolder.path) {
            panel.directoryURL = Self.suggestedFolder
        }
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        await scanFolder(folder)
    }

    func scanFolder(_ folder: URL) async {
        isScanning = true
        errorMessage = nil
        statusMessage = nil
        importedIDs = []
        do {
            scan = try await Task.detached { try Self.readFolder(folder) }.value
        } catch {
            scan = nil
            errorMessage = "Could not read \(folder.path): \(error.localizedDescription)"
        }
        isScanning = false
    }

    /// Classifies every item folder that contains a project.json. Scene .pkg files are never parsed.
    private nonisolated static func readFolder(_ folder: URL) throws -> WorkshopScan {
        let fm = FileManager.default
        // The user may pick the content folder (many items) or a single item folder.
        let folders: [URL]
        if fm.fileExists(atPath: folder.appendingPathComponent("project.json").path) {
            folders = [folder]
        } else {
            folders = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        var result = WorkshopScan()

        for dir in folders {
            let projectURL = dir.appendingPathComponent("project.json")
            guard fm.fileExists(atPath: projectURL.path) else { continue }
            let id = dir.lastPathComponent

            // Wallpaper Engine writes UTF-8 files that may start with a BOM; strip it before parsing.
            var data = (try? Data(contentsOf: projectURL)) ?? Data()
            if data.starts(with: [0xEF, 0xBB, 0xBF]) { data.removeFirst(3) }
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                result.unsupported.append(UnsupportedItem(id: id, title: id, reason: "project.json could not be parsed."))
                continue
            }

            let title = (json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
            let type = (json["type"] as? String)?.lowercased() ?? ""
            guard type == "video" else {
                let shown = type.isEmpty ? "unknown" : type
                result.unsupported.append(UnsupportedItem(
                    id: id, title: title,
                    reason: "Type \"\(shown)\" is not supported; LoopWall only plays video wallpapers."))
                continue
            }
            guard let file = json["file"] as? String, !file.isEmpty else {
                result.unsupported.append(UnsupportedItem(id: id, title: title, reason: "project.json has no video file."))
                continue
            }

            let videoURL = dir.appendingPathComponent(file).standardizedFileURL
            guard videoURL.path.hasPrefix(dir.standardizedFileURL.path + "/") else {
                result.unsupported.append(UnsupportedItem(id: id, title: title, reason: "The video path points outside the item folder."))
                continue
            }
            guard fm.fileExists(atPath: videoURL.path) else {
                result.unsupported.append(UnsupportedItem(id: id, title: title, reason: "Video file \"\(file)\" was not found (not downloaded yet?)."))
                continue
            }

            let ext = videoURL.pathExtension.lowercased()
            if ext == "pkg" {
                result.unsupported.append(UnsupportedItem(id: id, title: title, reason: ".pkg packages are not supported."))
            } else if playableExtensions.contains(ext) {
                result.importable.append(WorkshopItem(id: id, title: title, videoURL: videoURL))
            } else {
                result.needsConversion.append(WorkshopItem(id: id, title: title, videoURL: videoURL))
            }
        }
        return result
    }

    // MARK: - Import

    func importItem(_ item: WorkshopItem, into store: LibraryStore) async {
        busyItemID = item.id
        let errors = await store.importVideos([item.videoURL], names: [item.videoURL: item.title])
        busyItemID = nil
        if errors.isEmpty { importedIDs.insert(item.id) } else { errorMessage = errors.joined(separator: "\n") }
    }

    func importAllPlayable(into store: LibraryStore) async {
        for item in scan?.importable ?? [] where !importedIDs.contains(item.id) {
            await importItem(item, into: store)
        }
    }

    // MARK: - ffmpeg conversion (only if ffmpeg is already installed)

    /// Converts a non-playable video (e.g. .webm) to H.264/AAC .mp4, then imports it.
    func convertAndImport(_ item: WorkshopItem, into store: LibraryStore) async {
        guard let ffmpeg = ffmpegPath else {
            errorMessage = "ffmpeg is not installed, so this item cannot be converted."
            return
        }
        busyItemID = item.id
        statusMessage = "Converting \"\(item.title)\"… this can take a few minutes."
        errorMessage = nil
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        let input = item.videoURL.path
        let result = await Task.detached {
            Self.runProcess(ffmpeg, ["-nostdin", "-loglevel", "error", "-y", "-i", input,
                                     "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", "-preset", "medium",
                                     "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", output.path])
        }.value
        statusMessage = nil

        if result.status == 0 {
            let errors = await store.importVideos([output], names: [output: item.title])
            if errors.isEmpty { importedIDs.insert(item.id) } else { errorMessage = errors.joined(separator: "\n") }
        } else {
            errorMessage = "ffmpeg failed (exit \(result.status)): \(String(result.output.suffix(400)))"
        }
        try? FileManager.default.removeItem(at: output)   // temporary converted copy
        busyItemID = nil
    }

    // MARK: - Tool detection

    /// Looks for steamcmd and ffmpeg with `which`, in a login shell so Homebrew's PATH is included.
    func refreshTools() {
        Task {
            steamcmdPath = await Self.which("steamcmd")
            ffmpegPath = await Self.which("ffmpeg")
        }
    }

    private nonisolated static func which(_ tool: String) async -> String? {
        await Task.detached {
            let result = runProcess("/bin/zsh", ["-l", "-c", "which \(tool)"])
            let path = result.output.split(separator: "\n").last.map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return result.status == 0 && path?.hasPrefix("/") == true ? path : nil
        }.value
    }

    // MARK: - SteamCMD download helper

    /// Opens Terminal running steamcmd. The password and Steam Guard code are typed there by the user;
    /// this app never sees, stores or logs them. Only the username and the numeric item ID are used.
    func openDownloadInTerminal(username: String, workshopID: String) {
        errorMessage = nil
        guard let steamcmd = steamcmdPath else {
            errorMessage = "steamcmd was not found. Install it yourself, then reopen this window."
            return
        }
        // Strict validation: these values end up in a shell script.
        guard username.range(of: "^[A-Za-z0-9_.-]{1,64}$", options: .regularExpression) != nil else {
            errorMessage = "Enter your Steam username (letters, digits, '_', '.', '-')."
            return
        }
        guard workshopID.range(of: "^[0-9]{1,20}$", options: .regularExpression) != nil else {
            errorMessage = "The Workshop ID must be a number."
            return
        }

        let quotedPath = "'" + steamcmd.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = """
        #!/bin/zsh
        clear
        echo "Downloading Workshop item \(workshopID) as Steam user \(username)."
        echo "Type your Steam password and Steam Guard code here when SteamCMD asks."
        echo
        \(quotedPath) +@sSteamCmdForcePlatformType windows +login \(username) +workshop_download_item \(Self.appID) \(workshopID) +quit
        echo
        echo "Finished. Go back to the app and scan the Workshop folder."
        read -r "?Press Return to close this window."
        rm -f -- "$0"
        """
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("loopwall-steamcmd-\(UUID().uuidString).command")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            errorMessage = "Could not prepare the Terminal script: \(error.localizedDescription)"
            return
        }

        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([scriptURL], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in self?.errorMessage = "Could not open Terminal: \(error.localizedDescription)" }
        }
        statusMessage = "Terminal opened. Enter your password and Steam Guard code there, then scan the folder again."
    }

    // MARK: - Process helper

    private nonisolated static func runProcess(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
