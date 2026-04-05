import SwiftUI

@main
struct FolderPlayerApp: App {
    @StateObject private var player = AudioPlayerManager()
    @State private var selectedTab = 0

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
            .environmentObject(player)
        }
    }
}

// MARK: - Mini Player Modifier

private struct MiniPlayerModifier: ViewModifier {
    @EnvironmentObject var player: AudioPlayerManager
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
