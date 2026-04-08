# LocalMusic

A music player for locally stored audio files on iOS. Point it at a folder on your device or cloud storage and it becomes your library — no streaming service required.

## Features

- **Folder-based library** — pick any folder via the system document picker; tracks are scanned recursively
- **Rich metadata** — reads title, artist, album, artwork, and duration from file tags
- **Lyrics** — displays embedded unsynced and synced (SYLT) lyrics with auto-scrolling
- **Playlists** — discovers `.m3u` / `.m3u8` / `.pls` files and lets you create and edit your own
- **Now Playing** — full-screen artwork with ambient background color, seek bar, shuffle, and repeat modes
- **Lock screen & Control Center** — playback controls and now-playing info via `MPNowPlayingInfoCenter`
- **Search** — filter your library by title, artist, or album
- **Supported formats** — MP3, M4A, AAC, WAV, AIFF, FLAC, CAF, Opus

## Requirements

- Xcode 15+
- iOS 17.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build

```bash
# Install XcodeGen if you don't have it
brew install xcodegen

# Generate the Xcode project
xcodegen

# Open in Xcode
open LocalMusic.xcodeproj
```

Then build and run on a simulator or device (iOS 17+).

## Architecture

The app is a single-target SwiftUI project with a tab-based layout (Library, Now Playing, Playlists). Key components:

| File | Role |
|---|---|
| `LocalMusicApp` | App entry point; sets up the tab view and injects the shared player |
| `AudioPlayerManager` | `ObservableObject` wrapping `AVPlayer`; owns playback state, queue, shuffle/repeat logic, and lock-screen integration |
| `MetadataLoader` | Scans folders for audio files, extracts ID3/iTunes metadata and lyrics, parses and writes playlist files |
| `PersistenceManager` | Persists the selected folder (via security-scoped bookmarks) and caches the library as JSON |
| `LibraryView` | Displays all tracks with search, pull-to-refresh, and context menu for adding to playlists |
| `NowPlayingView` | Full-screen player with artwork, synced lyrics overlay, seek bar, and transport controls |
| `PlaylistsView` | Lists discovered and user-created playlists; supports creation and deletion |
| `DocumentPicker` | `UIViewControllerRepresentable` wrapper around `UIDocumentPickerViewController` for folder selection |

Data flows from `AudioPlayerManager` (injected as an `@EnvironmentObject`) down to all views. The library is cached to disk as JSON and refreshed in the background on each launch.

## License

[MPL 2.0](LICENSE)
