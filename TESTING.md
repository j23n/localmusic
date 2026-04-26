# Testing Strategy

LocalMusic currently has no tests. This document lays out a three-layer
strategy — unit, integration, UI — and the small refactors needed to make the
core logic testable without iOS hardware or real audio files.

## Goals and non-goals

- **Goal:** cover the bug-prone code first (binary parsers, queue/shuffle/repeat
  state machine, persistence migration). Make those tests fast (<1 s total) and
  deterministic so they run on every commit.
- **Goal:** integration coverage for disk-touching paths against real `FileManager`
  in temp directories — no brittle mocks of Apple frameworks.
- **Non-goal:** snapshot or pixel testing of SwiftUI views. SwiftUI internals
  shift between iOS versions; the cost-to-signal ratio isn't worth it for an app
  this size.
- **Non-goal:** mocking `AVPlayer`. We test the queue logic around it instead.

## Refactor seams to add first

Three small refactors unlock most of the logic for unit testing.

1. **`PersistenceManager`, `ArtworkCache`, `LyricsCache`** — accept an injected
   base `URL` (default: real `Documents/`). Lets tests point at a temp dir and
   avoid singleton pollution across runs.
2. **`AudioPlayerManager`** — extract a `PlaybackQueue` value type that owns
   `currentQueue`, `currentIndex`, `unshuffledQueue`, `repeatMode`,
   `shuffleEnabled`, and exposes `next()`, `previous(currentTime:)`,
   `toggleShuffle()`, `cycleRepeatMode()`. The manager keeps the AVFoundation
   wrapper. Highest-leverage refactor in the codebase.
3. Pull `SyncedLyricsView.activeIndex`, `formatDuration`, and `formatTime` into
   free functions or extensions so tests don't need a `View` instance.

## Layer 1 — Unit tests (fast, no filesystem)

### `Models.swift`

- `Track.stableID(for:)`
  - deterministic for same URL
  - different URLs → different IDs
  - `/foo/./bar` and `/foo/bar` collapse to the same ID via `.standardized`
  - output's variant/version bits set so `UUID` accepts the layout
- `RepeatMode` raw-value round-trip (it backs UserDefaults persistence)
- `TrackLyrics.isEmpty` — both nil; empty unsynced + nil synced; non-empty synced

### `MetadataLoader` — parsers (highest bug surface)

- `parseSYLT(data:)`
  - All four ID3 text encodings (`0` Latin-1, `1` UTF-16 w/ BOM, `2` UTF-16 BE,
    `3` UTF-8)
  - Timestamp format `2` (ms) and the fallback path
  - Short data (< 6 bytes) → nil
  - Empty body → nil
  - Whitespace-only lines filtered out
  - Output sorted by timestamp ascending
  - Truncated final string handled gracefully
- `parseM3U` (via `parsePlaylistContent`)
  - Skips `#EXTM3U`, comments, blank lines
  - Resolves relative paths against `baseDir`
  - Preserves the original `rawPath` alongside the resolved URL
- `parsePLS`
  - Matches `File1=`, `File2=` case-insensitively
  - Ignores `NumberOfEntries`, `Version`, `[playlist]`
  - Trailing whitespace on values trimmed
- `resolveTrackPath`
  - Empty → nil; `http://` / `https://` → nil
  - Absolute `/foo/bar.mp3` vs relative `bar.mp3`
  - Unsupported extension → nil; case-insensitive (`.MP3`)
- `relativePath(for:relativeTo:)`
  - Track inside baseDir → relative; outside → absolute
  - `baseDir` with and without trailing slash produce same result
- `buildM3U` / `buildPLS` (via `writePlaylist` to temp file)
  - M3U starts with `#EXTM3U`, one entry per track
  - PLS includes `NumberOfEntries=` and `Version=2`
- **Round-trip:** build → write → parse returns the same URLs

### `LibraryStore` (must run on `@MainActor`)

- `searchTracks(query:limit:)`
  - Empty query returns all (or first `limit`)
  - Matches title, artist, and album case-insensitively
  - `limit` honored
- `ingest` side effects (assert via public state)
  - `tracks`, `tracksByURL` keyed on `.standardized`
  - `searchKeys` are lowercased "title artist album" strings
- `displayTracks` / `sections` pipeline (use the `immediate: true` path or
  expose a test hook to bypass the 250 ms debounce)
  - Sort by title / artist / album / duration
  - Search filter applied; tie-breakers (artist sort falls back to title)
- Sectioning
  - `bucketByFirstLetter` — letters uppercased; non-letter starts → "#";
    whitespace-only string → "#"
  - `bucketByDuration` — boundaries (59.999, 60.0, 179.999, 180.0, …); empty
    buckets dropped; ordering preserved
- Playlist CRUD
  - `createPlaylist` with empty/whitespace name → nil
  - `createPlaylist` appends and re-sorts case-insensitively
  - `deletePlaylists` removes file from disk
  - `savePlaylist` updates the in-memory array and rewrites the file

### `PlaybackQueue` (after the AudioPlayerManager refactor)

- `play(track:queue:startIndex:)`
  - Shuffle off → `currentQueue == queue`, `currentIndex == startIndex`
  - Shuffle on → played track at index 0; remaining elements are a permutation
    of the rest
- `next()`
  - Advances index
  - End + `.off` → stops
  - End + `.all` → wraps to 0
  - `.one` → "seek to 0" signal (no index change)
  - Empty queue → no-op
- `previous(currentTime:)`
  - `currentTime > 3` → "seek to 0" signal, no index change
  - At index 0 + `.all` → wraps to last
  - At index 0 + `.off` → "seek to 0" signal
- `toggleShuffle()`
  - Turning on: current track survives at index 0; `unshuffledQueue` preserves
    the original
  - Turning off: `currentQueue` restored, `currentIndex` points at the same
    track
- `cycleRepeatMode()`: off → all → one → off
- UserDefaults persistence on init/didSet — use a dedicated
  `UserDefaults(suiteName:)` for tests

### Small helpers

- `Collection.subscript(safe:)` — out of bounds → nil; valid → element
- `SyncedLyricsView.activeIndex` (or extracted helper)
  - Empty lines → 0
  - currentTime before first → 0
  - Exact match on a timestamp
  - currentTime after last → last index
  - Monotonic across a sweep

## Layer 2 — Integration tests (real disk, temp dirs)

Each test uses `FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)`
and tears down in `tearDown`.

### Folder-scan end-to-end

Bundle a handful of short audio fixtures into the test bundle:

- 1-second silent MP3 with embedded ID3v2 + artwork
- M4A with iTunes lyrics
- MP3 with SYLT
- Unsupported `.txt`

Then assert:

- `MetadataLoader.scanFolder(at:)` returns the right count, recurses
  subfolders, skips unsupported extensions
- Tracks have title/artist/album extracted
- `ArtworkCache.hasArtwork` true for fixtures with artwork; false otherwise
- `LyricsCache.hasLyrics` true for fixtures with USLT/SYLT; lyrics decode
  round-trips
- `ScanProgress` callback receives monotonic `completed` ≤ `total`
- Stale artwork from a prior scan is removed if the metadata no longer carries it

### Playlist parse/write round-trip

Build a temp folder with three audio files plus an `.m3u` listing two real
entries and one bogus path:

- `parsePlaylist` returns 3 `trackURLs`/`rawPaths`; the missing one won't
  appear in `LibraryStore.resolved(from:)`
- Mutate the playlist, `writePlaylist`, re-parse → matches new state
- Same for `.pls`
- Latin-1-encoded m3u file decodes via the fallback path

### `PersistenceManager`

- `saveLibraryAsync` → `loadLibraryAsync` round-trip (slim format)
- `decodeAndMigrate` against fixed JSON blobs
  - Legacy with inline `artworkData` → `ArtworkCache` populated,
    `hasArtwork == true`
  - Legacy with inline `lyrics` / `syncedLyrics` → `LyricsCache` populated
  - Missing `id` → derives `Track.stableID(for:)`
  - Empty `artworkData` (zero bytes) doesn't create a cache file
- `folderContentModificationDate`
  - Touch a nested file → returned date increases
  - Empty folder → nil
- Bookmark save/load via an isolated `UserDefaults` suite

### `LibraryStore.bootstrap()` flow

- Pre-seed `library.json` in the injected docs dir; bootstrap loads cached
  tracks before any scan
- With `lastSynced` newer than folder mtime, no rescan is triggered (assert by
  inspecting `lastSynced` is unchanged and tracks match the cached fixture)

### Cache layer

- `ArtworkCache.storeSync` → `hasArtwork` true → `remove` deletes file and
  clears NSCache
- `ArtworkCache.thumbnail(for:pointSize:scale:)` against a real PNG fixture —
  non-nil result, dimensions ≤ requested
- `LyricsCache` round-trip; deleting the cache file invalidates `hasLyrics`

## Layer 3 — UI smoke tests (XCUITest, defer until L1 + L2 are stable)

`UIDocumentPickerViewController` can't be driven from XCUITest, so add a
debug-only launch argument (e.g., `--demo-library`) that points the app at a
fixture folder bundled with the UI test runner.

- Cold launch with no folder → onboarding visible
- With demo library → tap a row → mini-player appears with that title; Now
  Playing tab shows the track
- Play/pause icon toggles on tap
- Shuffle and repeat buttons cycle their visual state
- Pull-to-refresh on the library list completes without crashing

## Test-target wiring (`project.yml`)

```yaml
targets:
  LocalMusic:
    # ... existing ...

  LocalMusicTests:
    type: bundle.unit-test
    platform: iOS
    sources: [LocalMusicTests]
    dependencies:
      - target: LocalMusic
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        BUNDLE_LOADER: $(TEST_HOST)
        TEST_HOST: $(BUILT_PRODUCTS_DIR)/LocalMusic.app/LocalMusic

  LocalMusicUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [LocalMusicUITests]
    dependencies:
      - target: LocalMusic

schemes:
  LocalMusic:
    build:
      targets:
        LocalMusic: all
        LocalMusicTests: [test]
        LocalMusicUITests: [test]
    test:
      targets: [LocalMusicTests, LocalMusicUITests]
```

Then `xcodegen` and:

```sh
xcodebuild test \
  -scheme LocalMusic \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Suggested order

1. Add the test targets to `project.yml`, regenerate, get an empty test target
   running green.
2. Land the `PlaybackQueue` extraction from `AudioPlayerManager` and the
   `documentsURL` injection on `PersistenceManager` / caches. These unblock
   the highest-value tests.
3. Write `MetadataLoader` unit tests (parsers and round-trips). Biggest bug
   surface, no fixtures needed for the SYLT / M3U / PLS string parsing.
4. Write `PlaybackQueue` and `LibraryStore` unit tests.
5. Bundle a couple of short audio fixtures and write the folder-scan
   integration tests.
6. Cache + persistence integration tests.
7. UI smoke tests last, behind a debug launch arg.
