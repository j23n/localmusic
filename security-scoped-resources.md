# iOS Security-Scoped Resources — Research Findings

Findings from debugging FolderPlayer's folder access across app restarts on iOS.

## The Problem

When a user picks a folder via `UIDocumentPickerViewController`, the app gets temporary access to that folder. But after the app is killed and relaunched, the security-scoped bookmark must be used to regain access. In FolderPlayer, `startAccessingSecurityScopedResource()` was returning `false` on the bookmark-resolved URL after restart, and file access was failing with `FIGSANDBOX err=-17508` / `NSCocoaErrorDomain Code=257`.

## Key Findings

### 1. Bookmark Must Be Created While Security Scope Is Active

The picker URL has implicit temporary access — you don't need to call `startAccessingSecurityScopedResource()` to use it during the picker callback. However, to create a bookmark that **persists** the security scope, you must call `startAccessingSecurityScopedResource()` on the picker URL **before** creating the bookmark data. The scope token gets embedded into the bookmark data.

```swift
DocumentPicker { pickerURL in
    // Start access BEFORE creating bookmark
    _ = pickerURL.startAccessingSecurityScopedResource()
    PersistenceManager.shared.saveFolderBookmark(pickerURL)
    pickerURL.stopAccessingSecurityScopedResource()

    // Now resolve the bookmark for use
    if let resolvedURL = PersistenceManager.shared.loadFolderBookmark() {
        folderURL = resolvedURL
        scanFolder(resolvedURL)
    }
}
```

### 2. `startAccessingSecurityScopedResource()` Returning `false` Doesn't Necessarily Mean Failure

A `false` return can mean:
- The URL doesn't have a security scope (actual failure), OR
- Access is **already granted** via a cached sandbox extension

Due to sandbox extension caching, the system may have already granted access from a previous call or from the bookmark resolution itself. The recommendation is to **proceed with file access anyway** even when `false` is returned — only treat it as a real failure if the actual file operations fail.

```swift
func startAccessingFolder(_ url: URL) {
    stopAccessingCurrentFolder()
    let result = url.startAccessingSecurityScopedResource()
    // Store regardless — false can mean cached access
    activeSecurityScopedURL = url
}
```

### 3. iOS Simulator Is Unreliable for Testing Security-Scoped Bookmarks

The simulator sandbox doesn't fully mirror real device behavior for security-scoped resources. Bookmarks that fail on the simulator may work fine on a real device, and vice versa. Always test security-scoped bookmark persistence on a physical device.

### 4. `FileManager.enumerator` Breaks Security Scope

`FileManager.enumerator(at:)` resolves symlinks, producing paths like `/private/var/mobile/...` instead of `/var/mobile/...`. These resolved paths fall **outside** the security scope of the original folder URL, causing sandbox denials.

Fix: Use recursive `FileManager.contentsOfDirectory(at:)` instead, which preserves the parent URL's path prefix.

```swift
// BAD — resolves symlinks, breaks security scope
let enumerator = FileManager.default.enumerator(at: folderURL, ...)

// GOOD — preserves parent URL prefix
let contents = try FileManager.default.contentsOfDirectory(
    at: directory,
    includingPropertiesForKeys: [.isDirectoryKey],
    options: [.skipsHiddenFiles]
)
```

### 5. Bookmark Creation Options

Using `options: []` (empty) for bookmark creation works. `.minimalBookmark` may also work and produces smaller bookmark data — worth trying if `[]` causes issues on real devices.

### 6. Balance start/stop Calls

Each call to `startAccessingSecurityScopedResource()` should be balanced with exactly one `stopAccessingSecurityScopedResource()`. Multiple unbalanced `start` calls can confuse the system. Use a single "active folder" pattern:

```swift
private var activeSecurityScopedURL: URL?

func startAccessingFolder(_ url: URL) {
    stopAccessingCurrentFolder()  // stop previous
    _ = url.startAccessingSecurityScopedResource()
    activeSecurityScopedURL = url
}

private func stopAccessingCurrentFolder() {
    activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
    activeSecurityScopedURL = nil
}
```

### 7. Don't Call start/stop During Scanning

The folder scan (metadata loading) should NOT call `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` itself. The caller (LibraryView) opens the scope before scanning, and it stays open for the lifetime of the folder so playback can access files later.

## Summary of Fixes Applied to FolderPlayer

1. Switched from `FileManager.enumerator` to recursive `contentsOfDirectory(at:)` in `MetadataLoader`
2. Removed start/stop calls from `MetadataLoader` (caller manages scope)
3. Consolidated to single balanced start/stop pattern in `AudioPlayerManager`
4. Call `startAccessingSecurityScopedResource()` on picker URL before saving bookmark in `LibraryView`
5. Proceed with file access even when `startAccessingSecurityScopedResource()` returns `false`
6. Cache library to disk so tracks display immediately while rescan happens
7. Only replace cached tracks if rescan actually finds results (prevents empty library on failed rescan)
