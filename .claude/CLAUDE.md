# LocalMusic

iOS music player that plays audio files from a user-selected folder. SwiftUI, no external dependencies.

## Build

Project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.

```
xcodegen generate   # regenerate LocalMusic.xcodeproj
xcodebuild -project LocalMusic.xcodeproj -scheme LocalMusic -destination 'generic/platform=iOS' build
```

Requires Xcode 16+, targets iOS 18+, Swift 6 with `SWIFT_STRICT_CONCURRENCY: complete`. Unit tests live in `LocalMusicTests/` and run via `xcodebuild test`; CI runs them on every PR. Cross-app conventions are documented in `.claude/CONVENTIONS.md`.

## Architecture

Single-target SwiftUI app with three tabs: Library, Now Playing, Playlists. State lives in `@Observable` stores injected via `@Environment(_:)`.

```
LocalMusic/
  LocalMusicApp.swift         # @main; tab wiring, scene-phase rescan
  Logging.swift               # Log.<category> wrapping os.Logger
  Models/                     # Track, Playlist, RepeatMode, SyncedLyricLine
  Services/                   # AudioPlayerManager, LibraryStore, PlaybackQueue,
                              # MetadataLoader, PersistenceManager,
                              # ArtworkCache, LyricsCache
  Views/                      # LibraryView, NowPlayingView, PlaylistsView,
                              # PlaylistDetailView, MiniPlayerView, SettingsView
  Components/                 # ArtworkView, DocumentPicker
```

- `LocalMusicApp.swift` — Entry point; tab navigation, `@State` stores, `scenePhase`-driven `LibraryStore.checkForExternalChanges()`
- `Services/AudioPlayerManager.swift` — `@Observable @MainActor`; wraps `AVPlayer`, owns lock-screen/Control Center integration
- `Services/LibraryStore.swift` — `@Observable @MainActor`; slim `Track` array, debounced filter/sort pipeline, playlist CRUD
- `Services/MetadataLoader.swift` — Recursive folder scan, ID3/iTunes metadata extraction, playlist (m3u/pls) parsing and writing
- `Services/PersistenceManager.swift` — `@unchecked Sendable`; security-scoped folder bookmarks, JSON library cache, folder mtime
- `Models/Track.swift`, `Playlist.swift`, `RepeatMode.swift`, `SyncedLyricLine.swift` — slim value types

### Views

- `Views/LibraryView.swift` — Track list with search; `TrackRow` and `NowPlayingBars` components live here
- `Views/NowPlayingView.swift` — Full-screen player with artwork, ambient color, synced lyrics, seek bar
- `Views/PlaylistsView.swift` — Playlist list with creation/deletion; `PlaylistMosaicView` thumbnail component
- `Views/PlaylistDetailView.swift` — Playlist tracks with inline missing-file warnings; `AddTracksSheet`, `MissingTrackRow`
- `Views/MiniPlayerView.swift` — Compact bottom-bar player overlay
- `Views/SettingsView.swift` — Folder selection, rescan, stats
- `Components/DocumentPicker.swift` — `UIViewControllerRepresentable` wrapper for folder picker
- `Components/ArtworkView.swift` — async-loading artwork with placeholder

## Key patterns

- Folder access uses security-scoped bookmarks (`PersistenceManager`); `AudioPlayerManager.startAccessingFolder()` must be active for file reads
- Playlists store `trackURLs: [URL]` and parallel `rawPaths: [String]` — always keep both in sync when mutating
- Library tracks are matched to playlist entries by comparing `.standardized` URLs
- Playlist files are rewritten atomically on every mutation via `MetadataLoader.writePlaylist()`
