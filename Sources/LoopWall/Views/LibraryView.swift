import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var showImporter = false
    @State private var showWorkshop = false

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            if state.store.items.isEmpty {
                ContentUnavailableView("No wallpapers yet",
                                       systemImage: "film",
                                       description: Text("Drop .mp4, .mov or .m4v files here, or use Import."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(state.store.items) { item in
                            LibraryCell(item: item)
                        }
                    }
                    .padding(16)
                }
            }
            if let message = state.errorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(message).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button("Dismiss") { state.errorMessage = nil }
                }
                .padding(10)
                .background(.red.opacity(0.12))
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await state.importVideos(urls) }
            return true
        }
        .toolbar {
            ToolbarItem {
                Picker("Display", selection: $state.target) {
                    Text("All displays").tag(DisplayTarget.all)
                    ForEach(state.displays) { display in
                        Text(display.name).tag(DisplayTarget.display(display.id))
                    }
                }
            }
            ToolbarItem {
                Button("Import…", systemImage: "square.and.arrow.down") { showImporter = true }
            }
            ToolbarItem {
                Button("Wallpaper Engine…", systemImage: "arrow.down.app") { showWorkshop = true }
            }
            ToolbarItem {
                Button("Settings", systemImage: "gearshape") { openWindow(id: "settings") }
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.mpeg4Movie, .quickTimeMovie, UTType(filenameExtension: "m4v") ?? .movie],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await state.importVideos(urls) }
            case .failure(let error): state.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showWorkshop) {
            WorkshopImportView(steam: state.steam, store: state.store)
        }
        .onAppear { state.windowsChanged() }
    }
}

private struct LibraryCell: View {
    @EnvironmentObject var state: AppState
    let item: LibraryItem
    @State private var thumbnail: NSImage?
    @State private var thumbnailFailed = false

    private var isInUse: Bool { state.store.assignments.values.contains(item.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Rectangle().fill(.quaternary)
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFill()
                } else if thumbnailFailed {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: isInUse ? 3 : 0))
            Text(item.name).font(.callout).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture { state.apply(item) }
        .contextMenu {
            Button("Remove", role: .destructive) { state.remove(item) }
        }
        .task(id: item.id) {
            if let data = await state.store.thumbnailData(for: item), let image = NSImage(data: data) {
                thumbnail = image
            } else {
                thumbnailFailed = true
            }
        }
    }
}
