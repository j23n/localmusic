import AVFoundation
import MediaPlayer
import Observation
import UIKit

@Observable
@MainActor
final class AudioPlayerManager {

    // MARK: - Observed State

    var currentTrack: Track?
    var isPlaying: Bool = false
    var currentTime: Double = 0
    var duration: Double = 0
    var shuffleEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(shuffleEnabled, forKey: "shuffleEnabled")
            queue.shuffleEnabled = shuffleEnabled
        }
    }
    var repeatMode: RepeatMode = .off {
        didSet {
            UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode")
            queue.repeatMode = repeatMode
        }
    }
    var currentQueue: [Track] = []
    var currentIndex: Int = 0

    // MARK: - Private

    /// Pure state machine for queue/shuffle/repeat. We mirror the relevant
    /// fields onto the observed properties above after each mutation so the
    /// existing view code keeps observing the same surface.
    private var queue = PlaybackQueue()

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var activeSecurityScopedURL: URL?

    // MARK: - Init

    init() {
        let storedShuffle = UserDefaults.standard.bool(forKey: "shuffleEnabled")
        let storedMode: RepeatMode = {
            guard let raw = UserDefaults.standard.string(forKey: "repeatMode"),
                  let mode = RepeatMode(rawValue: raw) else { return .off }
            return mode
        }()
        shuffleEnabled = storedShuffle
        repeatMode = storedMode
        queue.shuffleEnabled = storedShuffle
        queue.repeatMode = storedMode
        configureAudioSession()
        configureRemoteCommands()
    }

    deinit {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
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
            Log.player.error("Failed to configure audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Remote Commands

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
    }

    // MARK: - Folder Access

    /// Begin security-scoped access for a URL and keep it open
    /// until a new folder is opened or the manager is deallocated.
    func startAccessingFolder(_ url: URL) {
        stopAccessingCurrentFolder()
        // Return value is intentionally ignored: `false` can mean access is
        // already cached via a sandbox extension, so files may still be
        // readable. We only need to call stopAccessing to balance the count.
        _ = url.startAccessingSecurityScopedResource()
        activeSecurityScopedURL = url
    }

    private func stopAccessingCurrentFolder() {
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        activeSecurityScopedURL = nil
    }

    // MARK: - Playback Control

    func play(track: Track, queue tracks: [Track], startIndex: Int) {
        let action = queue.play(track: track, queue: tracks, startIndex: startIndex)
        syncPublishedFromQueue()
        apply(action)
    }

    func setQueue(_ tracks: [Track], startIndex: Int) {
        let action = queue.setQueue(tracks, startIndex: startIndex)
        syncPublishedFromQueue()
        apply(action)
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
        let action = queue.next()
        syncPublishedFromQueue()
        apply(action)
    }

    func previous() {
        let action = queue.previous(currentTime: currentTime)
        syncPublishedFromQueue()
        apply(action)
    }

    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        updateNowPlayingElapsed()
    }

    // MARK: - Shuffle Toggle

    func toggleShuffle() {
        queue.toggleShuffle(currentTrackID: currentTrack?.id)
        // Keep the published flag in sync without retriggering the didSet
        // (which would write back into `queue`).
        if shuffleEnabled != queue.shuffleEnabled {
            shuffleEnabled = queue.shuffleEnabled
        }
        syncPublishedFromQueue()
    }

    func cycleRepeatMode() {
        queue.cycleRepeatMode()
        if repeatMode != queue.repeatMode {
            repeatMode = queue.repeatMode
        }
    }

    // MARK: - Action Dispatch

    private func apply(_ action: PlaybackQueue.Action) {
        switch action {
        case .load(let index):
            if let track = queue.currentQueue[safe: index] {
                loadAndPlay(track)
            }
        case .restart:
            seek(to: 0)
            player?.play()
            isPlaying = true
        case .seekToZero:
            seek(to: 0)
        case .stop:
            isPlaying = false
            player?.pause()
        case .noop:
            break
        }
    }

    private func syncPublishedFromQueue() {
        if currentQueue != queue.currentQueue { currentQueue = queue.currentQueue }
        if currentIndex != queue.currentIndex { currentIndex = queue.currentIndex }
    }

    // MARK: - Private Helpers

    private func loadAndPlay(_ track: Track) {
        removeTimeObserver()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil

        let item = AVPlayerItem(url: track.url)

        if player == nil {
            player = AVPlayer(playerItem: item)
        } else {
            player?.replaceCurrentItem(with: item)
        }

        currentTrack = track
        duration = track.duration
        currentTime = 0

        // Wait for the item to be ready before playing.
        //
        // The KVO callback runs on a background thread; hop to MainActor and
        // re-check that the player is still pointing at the same item, since
        // rapid track changes can leave a queued .readyToPlay block in flight
        // after we've moved on.
        let observedItemRef = ObjectIdentifier(item)
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            let status = observedItem.status
            let errorDescription = observedItem.error.map { String(describing: $0) } ?? "nil"
            Task { @MainActor [weak self] in
                guard let self,
                      let currentItem = self.player?.currentItem,
                      ObjectIdentifier(currentItem) == observedItemRef
                else { return }
                switch status {
                case .readyToPlay:
                    self.player?.play()
                    self.isPlaying = true
                    self.updateNowPlayingInfo()
                case .failed:
                    Log.player.error("AVPlayerItem failed: \(errorDescription, privacy: .public)")
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
            Task { @MainActor in self?.next() }
        }
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = CMTimeGetSeconds(time)
            Task { @MainActor [weak self] in
                guard let self else { return }
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
    }

    private func removeTimeObserver() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
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
                guard let image = await ArtworkCache.thumbnail(for: url, pointSize: 256, scale: scale)
                else { return }
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
