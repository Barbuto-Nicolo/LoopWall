import SwiftUI

/// Sheet for importing Wallpaper Engine video items and the optional SteamCMD helper.
struct WorkshopImportView: View {
    @ObservedObject var steam: SteamImporter
    let store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var workshopID = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Import from Wallpaper Engine").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    scanSection
                    resultSections
                    downloadSection
                }
                .padding()
            }
            if let message = steam.errorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.red.opacity(0.12))
            } else if let message = steam.statusMessage {
                Text(message)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary)
            }
        }
        .frame(width: 640, height: 600)
        .onAppear { steam.refreshTools() }
    }

    // MARK: - Scan

    private var scanSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workshop folder").font(.subheadline.bold())
            Text("Choose the folder that contains the item folders (each with a project.json). Suggested: \(SteamImporter.suggestedFolder.path)")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Choose Folder and Scan…") { Task { await steam.chooseFolderAndScan() } }
                    .disabled(steam.isScanning || steam.busyItemID != nil)
                if steam.isScanning { ProgressView().controlSize(.small) }
            }
        }
    }

    @ViewBuilder private var resultSections: some View {
        if let scan = steam.scan {
            if scan.importable.isEmpty && scan.needsConversion.isEmpty && scan.unsupported.isEmpty {
                Text("No items with a project.json were found in that folder.").foregroundStyle(.secondary)
            }
            if !scan.importable.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Ready to import (\(scan.importable.count))").font(.subheadline.bold())
                        Spacer()
                        Button("Import All") { Task { await steam.importAllPlayable(into: store) } }
                            .disabled(steam.busyItemID != nil)
                    }
                    ForEach(scan.importable) { item in
                        row(item, actionTitle: "Import") { await steam.importItem(item, into: store) }
                    }
                }
            }
            if !scan.needsConversion.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Needs conversion (\(scan.needsConversion.count))").font(.subheadline.bold())
                    Text(steam.ffmpegPath == nil
                         ? "AVFoundation cannot play these formats and ffmpeg is not installed, so they cannot be imported."
                         : "AVFoundation cannot play these formats. They can be converted to H.264 .mp4 with your installed ffmpeg.")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(scan.needsConversion) { item in
                        row(item, actionTitle: "Convert & Import", disabled: steam.ffmpegPath == nil) {
                            await steam.convertAndImport(item, into: store)
                        }
                    }
                }
            }
            if !scan.unsupported.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Not supported (\(scan.unsupported.count))").font(.subheadline.bold())
                    ForEach(scan.unsupported) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text("\(item.id): \(item.reason)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func row(_ item: WorkshopItem, actionTitle: String, disabled: Bool = false,
                     action: @escaping () async -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                Text(item.id).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if steam.busyItemID == item.id {
                ProgressView().controlSize(.small)
            } else if steam.importedIDs.contains(item.id) {
                Label("Imported", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button(actionTitle) { Task { await action() } }
                    .disabled(disabled || steam.busyItemID != nil)
            }
        }
    }

    // MARK: - SteamCMD helper

    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Download by Workshop ID (optional)").font(.subheadline.bold())
            if let path = steam.steamcmdPath {
                Text("steamcmd found: \(path)").font(.callout).foregroundStyle(.secondary)
                Text("Enter only your Steam username. The password and Steam Guard code are typed by you in the Terminal window that opens; this app never sees them.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    TextField("Steam username", text: $username).textFieldStyle(.roundedBorder)
                    TextField("Workshop ID", text: $workshopID).textFieldStyle(.roundedBorder)
                    Button("Open Terminal") {
                        steam.openDownloadInTerminal(username: username, workshopID: workshopID)
                    }
                }
            } else {
                Text("steamcmd was not found (`which steamcmd`). Install it yourself to enable this helper; this app never downloads it.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
