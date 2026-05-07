import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library

    private static let githubURL = URL(string: "https://github.com/j23n/localmusic")!

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
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

                    Button {
                        Task { await library.rescan() }
                    } label: {
                        Label("Reload Music", systemImage: "arrow.clockwise")
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

                Section("Stats") {
                    LabeledContent("Total Songs", value: "\(library.tracks.count)")
                    LabeledContent("Total Playlists", value: "\(library.playlists.count)")
                }

                Section("Diagnostics") {
                    NavigationLink {
                        LogsView()
                    } label: {
                        Label("Logs", systemImage: "doc.text.magnifyingglass")
                    }
                    LabeledContent("Version", value: appVersion)
                }

                Section("About") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("LocalMusic plays audio files from a folder of your choice — no streaming, no accounts.")
                            .font(.callout)

                        Text("Found a bug or have feedback? Open an issue or get in touch:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    Button {
                        openURL(Self.githubURL)
                    } label: {
                        LabeledContent {
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                    .tint(.primary)
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
