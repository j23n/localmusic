import AVFoundation
import Combine
import MediaPlayer
import UIKit

final class AudioPlayerManager: ObservableObject {

    // MARK: - Published State

    @Published var currentTrack: Track?
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var shuffleEnabled: Bool = false {
        didSet { UserDefaults.standard.set(shuffleEnabled, forKey: "shuffleEnabled") }
    }
    @Published var repeatMode: RepeatMode = .off {
        didSet { UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode") }
    }
    @Published var currentQueue: [Track] = []
    @Published var currentIndex: Int = 0

    // MARK: - Private

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var unshuffledQueue: [Track] = []
    private var activeSecurityScopedURL: URL?

    // MARK: - Init

    init() {
        shuffleEnabled = UserDefaults.standard.bool(forKey: "shuffleEnabled")
        if let raw = UserDefaults.standard.string(forKey: "repeatMode"),
           let mode = RepeatMode(rawValue: raw) {
            repeatMode = mode
        }
        configureAudioSession()
        configureRemoteCommands()
    }

    deinit {
        removeTimeObserver()
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        statusObserver?.invalidate()
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    // MARK: - Remote Commands

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
    }

    // MARK: - Folder Access

    /// Begin security-scoped access for a URL and keep it open
    /// until a new folder is opened or the manager is deallocated.
    func startAccessingFolder(_ url: URL) {
        stopAccessingCurrentFolder()
        let result = url.startAccessingSecurityScopedResource()
        print("[LocalMusic] startAccessingFolder: \(url.path)")
        print("[LocalMusic] startAccessingSecurityScopedResource returned: \(result)")
        // Store regardless of return value — `false` can mean access is
        // already cached via a sandbox extension, so files may still be readable.
        activeSecurityScopedURL = url
    }

    private func stopAccessingCurrentFolder() {
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        activeSecurityScopedURL = nil
    }

    // MARK: - Playback Control

    func play(track: Track, queue: [Track], startIndex: Int) {
        unshuffledQueue = queue
        if shuffleEnabled {
            var shuffled = queue
            if startIndex < shuffled.count {
                shuffled.remove(at: startIndex)
                shuffled.shuffle()
                shuffled.insert(track, at: 0)
            }
            currentQueue = shuffled
            currentIndex = 0
        } else {
            currentQueue = queue
            currentIndex = startIndex
        }
        loadAndPlay(track)
    }

    func setQueue(_ tracks: [Track], startIndex: Int) {
        unshuffledQueue = tracks
        if shuffleEnabled {
            let track = tracks[startIndex]
            var shuffled = tracks
            shuffled.remove(at: startIndex)
            shuffled.shuffle()
            shuffled.insert(track, at: 0)
            currentQueue = shuffled
            currentIndex = 0
        } else {
            currentQueue = tracks
            currentIndex = startIndex
        }
        if let track = currentQueue[safe: currentIndex] {
            loadAndPlay(track)
        }
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlayingElapsed()
    }

    func next() {
        guard !currentQueue.isEmpty else { return }

        if repeatMode == .one {
            seek(to: 0)
            player?.play()
            isPlaying = true
            return
        }

        let nextIndex = currentIndex + 1
        if nextIndex < currentQueue.count {
            currentIndex = nextIndex
            if let track = currentQueue[safe: currentIndex] {
                loadAndPlay(track)
            }
        } else if repeatMode == .all {
            currentIndex = 0
            if let track = currentQueue[safe: 0] {
                loadAndPlay(track)
            }
        } else {
            isPlaying = false
            player?.pause()
        }
    }

    func previous() {
        guard !currentQueue.isEmpty else { return }

        if currentTime > 3 {
            seek(to: 0)
            return
        }

        let prevIndex = currentIndex - 1
        if prevIndex >= 0 {
            currentIndex = prevIndex
            if let track = currentQueue[safe: currentIndex] {
                loadAndPlay(track)
            }
        } else if repeatMode == .all {
            currentIndex = currentQueue.count - 1
            if let track = currentQueue[safe: currentIndex] {
                loadAndPlay(track)
            }
        } else {
            seek(to: 0)
        }
    }

    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        updateNowPlayingElapsed()
    }

    // MARK: - Shuffle Toggle

    func toggleShuffle() {
        shuffleEnabled.toggle()
        guard !currentQueue.isEmpty, let current = currentTrack else { return }

        if shuffleEnabled {
            unshuffledQueue = currentQueue
            var shuffled = currentQueue.filter { $0.id != current.id }
            shuffled.shuffle()
            shuffled.insert(current, at: 0)
            currentQueue = shuffled
            currentIndex = 0
        } else {
            if let idx = unshuffledQueue.firstIndex(where: { $0.id == current.id }) {
                currentQueue = unshuffledQueue
                currentIndex = idx
            }
        }
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    // MARK: - Private Helpers

    private func loadAndPlay(_ track: Track) {
        removeTimeObserver()
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil

        print("[LocalMusic] loadAndPlay: \(track.url.path)")
        print("[LocalMusic] activeSecurityScopedURL: \(activeSecurityScopedURL?.path ?? "nil")")
        print("[LocalMusic] track URL starts with folder URL: \(activeSecurityScopedURL.map { track.url.path.hasPrefix($0.path) } ?? false)")

        // Test if we can read the file directly
        let readable = FileManager.default.isReadableFile(atPath: track.url.path)
        print("[LocalMusic] FileManager.isReadableFile: \(readable)")

        let item = AVPlayerItem(url: track.url)

        if player == nil {
            player = AVPlayer(playerItem: item)
        } else {
            player?.replaceCurrentItem(with: item)
        }

        currentTrack = track
        duration = track.duration
        currentTime = 0

        // Wait for the item to be ready before playing
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                switch observedItem.status {
                case .readyToPlay:
                    self.player?.play()
                    self.isPlaying = true
                    self.updateNowPlayingInfo()
                case .failed:
                    print("AVPlayerItem failed: \(String(describing: observedItem.error))")
                    self.isPlaying = false
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }

        addTimeObserver()

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.next()
        }
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = CMTimeGetSeconds(time)
            if !seconds.isNaN && !seconds.isInfinite {
                self.currentTime = seconds
            }
            if let itemDuration = self.player?.currentItem?.duration {
                let dur = CMTimeGetSeconds(itemDuration)
                if !dur.isNaN && !dur.isInfinite {
                    self.duration = dur
                }
            }
        }
    }

    private func removeTimeObserver() {
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else { return }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime
        ]

        if let image = ArtworkCache.cachedFullImage(for: track.url)
            ?? ArtworkCache.cachedThumbnail(for: track.url) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if track.hasArtwork
            && ArtworkCache.cachedFullImage(for: track.url) == nil
            && ArtworkCache.cachedThumbnail(for: track.url) == nil {
            let url = track.url
            let scale = UIScreen.main.scale
            Task { [weak self] in
                if let image = await ArtworkCache.thumbnail(for: url, pointSize: 256, scale: scale) {
                    await MainActor.run {
                        guard let self,
                              self.currentTrack?.url == url,
                              var info = MPNowPlayingInfoCenter.default().nowPlayingInfo
                        else { return }
                        info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                    }
                }
            }
        }
    }

    private func updateNowPlayingElapsed() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

// MARK: - Safe Collection Access

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
