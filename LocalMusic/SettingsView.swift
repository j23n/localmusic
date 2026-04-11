import SwiftUI

struct SettingsView: View {
    @Binding var folderURL: URL?
    let trackCount: Int
    let playlistCount: Int
    let onRescan: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showFolderPicker = false
    @State private var lastSynced: Date? = PersistenceManager.shared.loadLastSynced()

    var body: some View {
        NavigationStack {
            List {
                Section("Music Folder") {
                    Button {
                        showFolderPicker = true
                    } label: {
                        LabeledContent {
                            Text(folderURL?.lastPathComponent ?? "Not selected")
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Folder", systemImage: "folder")
                        }
                    }
                    .tint(.primary)

                    Button("Reload Music") {
                        onRescan()
                        lastSynced = PersistenceManager.shared.loadLastSynced()
                    }

                    if let lastSynced {
                        LabeledContent("Last Synced", value: lastSynced, format: .dateTime)
                    }
                }

                Section("Info") {
                    LabeledContent("Total Songs", value: "\(trackCount)")
                    LabeledContent("Total Playlists", value: "\(playlistCount)")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                DocumentPicker { pickerURL in
                    _ = pickerURL.startAccessingSecurityScopedResource()
                    PersistenceManager.shared.saveFolderBookmark(pickerURL)
                    pickerURL.stopAccessingSecurityScopedResource()

                    if let resolvedURL = PersistenceManager.shared.loadFolderBookmark() {
                        folderURL = resolvedURL
                        onRescan()
                        lastSynced = PersistenceManager.shared.loadLastSynced()
                    }
                }
            }
        }
    }
}
