import SwiftUI

@main
struct LocalMusicApp: App {
    @State private var player = AudioPlayerManager()
    @State private var library = LibraryStore()
    @State private var selectedTab = 0

    @Environment(\.scenePhase) private var scenePhase

    init() {
        Log.ui.info("App launched")
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                LibraryView()
                    .miniPlayer { selectedTab = 1 }
                    .tabItem {
                        Label("Library", systemImage: "music.note.list")
                    }
                    .tag(0)

                NowPlayingView()
                    .tabItem {
                        Label("Now Playing", systemImage: "play.circle.fill")
                    }
                    .tag(1)

                PlaylistsView()
                    .miniPlayer { selectedTab = 1 }
                    .tabItem {
                        Label("Playlists", systemImage: "rectangle.stack.fill")
                    }
                    .tag(2)
            }
            .environment(player)
            .environment(library)
            .task {
                await library.bootstrap()
                if let url = library.folderURL {
                    player.startAccessingFolder(url)
                }
            }
            .onChange(of: library.folderURL) { _, newValue in
                if let url = newValue {
                    Log.ui.info("Folder URL changed: \(url.lastPathComponent)")
                    player.startAccessingFolder(url)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                Log.ui.debug("Scene phase: \(String(describing: phase))")
                if phase == .active {
                    Task { await library.checkForExternalChanges() }
                }
            }
        }
    }
}

// MARK: - Mini Player Modifier

private struct MiniPlayerModifier: ViewModifier {
    @Environment(AudioPlayerManager.self) private var player
    let onTap: () -> Void

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if player.currentTrack != nil {
                MiniPlayerView(onTap: onTap)
            }
        }
    }
}

extension View {
    func miniPlayer(onTap: @escaping () -> Void) -> some View {
        modifier(MiniPlayerModifier(onTap: onTap))
    }
}
