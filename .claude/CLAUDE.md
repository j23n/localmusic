# LocalMusic

iOS music player that plays audio files from a user-selected folder. SwiftUI, no external dependencies.

## Build

Project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.

```
xcodegen generate   # regenerate LocalMusic.xcodeproj
xcodebuild -project LocalMusic.xcodeproj -scheme LocalMusic -destination 'generic/platform=iOS' build
```

Requires Xcode 15+, targets iOS 17+. No tests or linter configured.

## Architecture

Single-target SwiftUI app with three tabs: Library, Now Playing, Playlists.

- `LocalMusicApp.swift` — Entry point; tab navigation, injects `AudioPlayerManager` as environment object
- `AudioPlayerManager.swift` — Wraps `AVPlayer`; queue, shuffle/repeat, lock-screen/Control Center integration
- `MetadataLoader.swift` — Recursive folder scan, ID3/iTunes metadata extraction, playlist (m3u/pls) parsing and writing
- `PersistenceManager.swift` — Security-scoped folder bookmarks, JSON library cache
- `Models.swift` — `Track`, `Playlist`, `SyncedLyricLine`, `RepeatMode`

### Views

- `LibraryView.swift` — Track list with search; `TrackRow` and `NowPlayingBars` components live here
- `NowPlayingView.swift` — Full-screen player with artwork, ambient color, synced lyrics, seek bar
- `PlaylistsView.swift` — Playlist list with creation/deletion; `PlaylistMosaicView` thumbnail component
- `PlaylistDetailView.swift` — Playlist tracks with inline missing-file warnings; `AddTracksSheet`, `MissingTrackRow`
- `MiniPlayerView.swift` — Compact bottom-bar player overlay
- `SettingsView.swift` — Folder selection, rescan, stats
- `DocumentPicker.swift` — `UIViewControllerRepresentable` wrapper for folder picker

## Key patterns

- Folder access uses security-scoped bookmarks (`PersistenceManager`); `AudioPlayerManager.startAccessingFolder()` must be active for file reads
- Playlists store `trackURLs: [URL]` and parallel `rawPaths: [String]` — always keep both in sync when mutating
- Library tracks are matched to playlist entries by comparing `.standardized` URLs
- Playlist files are rewritten atomically on every mutation via `MetadataLoader.writePlaylist()`
