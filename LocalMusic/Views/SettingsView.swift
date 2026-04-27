import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library

    @Environment(\.dismiss) private var dismiss
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section("Music Folder") {
                    Button {
                        showFolderPicker = true
                    } label: {
                        LabeledContent {
                            Text(library.folderURL?.lastPathComponent ?? "Not selected")
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Folder", systemImage: "folder")
                        }
                    }
                    .tint(.primary)

                    Button("Reload Music") {
                        Task { await library.rescan() }
                    }
                    .disabled(library.folderURL == nil || library.isScanning)

                    if let lastSynced = library.lastSynced {
                        LabeledContent("Last Synced", value: lastSynced, format: .dateTime)
                    }

                    if library.isScanning {
                        if let progress = library.scanProgress, progress.total > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: Double(progress.completed),
                                             total: Double(max(progress.total, 1)))
                                Text("Scanning \(progress.completed) of \(progress.total)…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        } else {
                            HStack {
                                ProgressView()
                                Text("Scanning folder…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Info") {
                    LabeledContent("Total Songs", value: "\(library.tracks.count)")
                    LabeledContent("Total Playlists", value: "\(library.playlists.count)")
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
                    // The picker's URL carries a transient security scope that
                    // must be claimed and turned into a bookmark synchronously
                    // here; the rescan can then run as a Task.
                    _ = pickerURL.startAccessingSecurityScopedResource()
                    PersistenceManager.shared.saveFolderBookmark(pickerURL)
                    pickerURL.stopAccessingSecurityScopedResource()
                    Task {
                        await library.adoptSavedFolder()
                    }
                }
            }
        }
    }
}
