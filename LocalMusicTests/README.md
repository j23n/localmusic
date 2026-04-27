# Tests

Unit and integration tests for LocalMusic. Run via:

```sh
xcodegen
xcodebuild test \
  -scheme LocalMusic \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

CI runs the suite on every PR via `.github/workflows/test.yml`.

## Layout

| File | Coverage |
|---|---|
| `Fixtures.swift` | Shared `Track` builders for in-memory tests |
| `PlaybackQueueTests.swift` | Queue/shuffle/repeat state machine; `Action` dispatch |
| `MetadataLoaderTests.swift` | SYLT (UTF-8/Latin-1/UTF-16BE), m3u/pls parsing, path resolution, write→parse round-trip |
| `TrackTests.swift` | `Track.stableID` determinism + RFC 4122 bits, `RepeatMode` raw values, `TrackLyrics` Codable |
| `LibraryStoreTests.swift` | search, sort (title/artist/album/duration), sectioning (first letter + duration buckets), playlist CRUD, URL standardization |
| `HelpersTests.swift` | `Collection[safe:]`, `SyncedLyricsView.activeIndex` binary search |
| `PersistenceManagerTests.swift` | library round-trip, legacy → slim migration, folder mtime |
| `ArtworkCacheTests.swift` | key/path determinism, store/remove, ImageIO downsampling |
| `LyricsCacheTests.swift` | round-trip, empty-deletes-file, async remove, URL standardization |

## Refactor seams

These keep the production code testable. Don't remove without a replacement.

- `PlaybackQueue` (`LocalMusic/PlaybackQueue.swift`) — pure value-type state machine. `AudioPlayerManager` delegates to it and applies a returned `Action`.
- `PersistenceManager.init(documentsURL:userDefaults:)` — tests inject a temp dir and a private `UserDefaults` suite.
- `ArtworkCache.directoryOverride` / `LyricsCache.directoryOverride` — `#if DEBUG` only. Set in `setUp` / cleared in `tearDown`. Not parallel-test safe.
- `LibraryStore._testSeedTracks` / `_testWaitForApply` / `_testSetFolderURL` — `#if DEBUG` only. Drive the display pipeline without disk.
- `SyncedLyricsView.activeIndex(in:at:)` — static helper so tests don't need a `View`.

## Follow-ups

Open work, ordered by value:

1. **Folder-scan integration tests** with real audio fixtures. Need a small bundle of MP3/M4A files with embedded ID3v2 + iTunes metadata + USLT/SYLT lyrics, exercised against `MetadataLoader.scanFolder(at:)`. Synthesize via `AVAssetWriter` at test time, or check in.
2. **UI smoke tests** (XCUITest). `UIDocumentPickerViewController` can't be driven from XCUITest, so requires a debug-only `--demo-library` launch arg pointing at a fixture folder bundled with the UI test runner. Cover: onboarding → folder selection → tap row → mini-player → Now Playing tab → transport controls.
3. **Deterministic `_testFlushIO`** on `ArtworkCache` / `LyricsCache`. `remove` currently polls disk for up to 1 s. A `ioQueue.sync {}` helper would remove the flake risk on loaded CI.
4. **DEBUG-tunable debounce** on `LibraryStore.scheduleApply`. The 250 ms sleep makes search-pipeline tests slow; an injectable interval keeps the suite fast.
5. **Parallel-test safety** for the cache `directoryOverride` hooks. Either thread the directory through an instance, or document the constraint via an `xctestplan` that disables parallelization.
