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
    @ObservationIgnored private var queue = PlaybackQueue()

    /// AVFoundation/UIKit handles read-and-cleared from `deinit`, which
    /// Swift 6 treats as nonisolated even when the enclosing class is
    /// `@MainActor`. They're only ever written from MainActor methods, but
    /// the deinit is the one place we need to reach them off-actor; the
    /// `nonisolated(unsafe)` escape hatch keeps the rest of the type
    /// MainActor-isolated without a separate cleanup actor.
    @ObservationIgnored nonisolated(unsafe) private var player: AVPlayer?
    @ObservationIgnored nonisolated(unsafe) private var timeObserver: Any?
    @ObservationIgnored nonisolated(unsafe) private var endObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) private var statusObserver: NSKeyValueObservation?
    @ObservationIgnored nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) private var routeChangeObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) private var activeSecurityScopedURL: URL?

    /// Remembered across an audio-session interruption so we can resume
    /// only when the system says we should and we were actually playing.
    @ObservationIgnored private var wasPlaying = false

    /// Consecutive `.failed` item loads. Reset on `.readyToPlay`. Capped so
    /// a run of broken files (or Repeat One on one broken file) cannot loop.
    @ObservationIgnored private var consecutiveLoadFailures = 0

    /// `ProcessInfo.systemUptime` of the last now-playing center progress
    /// write from the periodic time observer. UI `currentTime` still updates
    /// every 0.5s; center writes are throttled to ~1s.
    @ObservationIgnored private var lastNowPlayingProgressWrite: TimeInterval = 0

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
        observeAudioSessionEvents()
    }

    deinit {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
        statusObserver?.invalidate()
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {
            Log.player.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    private func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Log.player.error("Failed to activate audio session: \(error.localizedDescription)")
        }
    }

    private func observeAudioSessionEvents() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleInterruption(notification) }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleRouteChange(notification) }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            wasPlaying = isPlaying
            pause()
        case .ended:
            let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) && wasPlaying {
                play()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        if reason == .oldDeviceUnavailable {
            pause()
        }
    }

    // MARK: - Remote Commands

    /// `player` is `nonisolated(unsafe)`, so the command-center callback
    /// (which may run off-main) can decide whether there is an item without
    /// hopping first. The actual play/pause still hops to MainActor.
    nonisolated private var hasNowPlayingItem: Bool {
        player?.currentItem != nil
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self, self.hasNowPlayingItem else {
                return .noActionableNowPlayingItem
            }
            Task { @MainActor in self.play() }
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.hasNowPlayingItem else {
                return .noActionableNowPlayingItem
            }
            Task { @MainActor in self.pause() }
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
        Log.player.info("Play: \(track.title) — \(track.artist) (queue: \(tracks.count), index: \(startIndex))")
        consecutiveLoadFailures = 0
        let action = queue.play(track: track, queue: tracks, startIndex: startIndex)
        syncPublishedFromQueue()
        apply(action)
    }

    func setQueue(_ tracks: [Track], startIndex: Int) {
        Log.player.info("Set queue: \(tracks.count) tracks, startIndex: \(startIndex)")
        consecutiveLoadFailures = 0
        let action = queue.setQueue(tracks, startIndex: startIndex)
        syncPublishedFromQueue()
        apply(action)
    }

    /// Resume playback. Idempotent: never pauses.
    func play() {
        guard let player else { return }
        activateAudioSession()
        player.play()
        isPlaying = true
        updateNowPlayingElapsed()
    }

    /// Pause playback. Idempotent: never resumes.
    func pause() {
        guard let player else { return }
        player.pause()
        isPlaying = false
        updateNowPlayingElapsed()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
        Log.player.debug("Toggle play/pause → \(isPlaying ? "playing" : "paused")")
    }

    /// User-initiated Next (in-app button and remote `nextTrackCommand`).
    /// Uses `skipForward()` so Repeat One cannot trap the listener.
    func next() {
        Log.player.debug("Skip to next")
        let action = queue.skipForward()
        syncPublishedFromQueue()
        apply(action)
    }

    func previous() {
        Log.player.debug("Skip to previous (currentTime: \(String(format: "%.1f", currentTime)))")
        let action = queue.previous(currentTime: currentTime)
        syncPublishedFromQueue()
        apply(action)
    }

    func seek(to time: Double, completion: (@MainActor () -> Void)? = nil) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        currentTime = time
        updateNowPlayingElapsed()

        guard let player else {
            completion?()
            return
        }

        let observedItemRef = player.currentItem.map { ObjectIdentifier($0) }
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, finished else { return }
                if let observedItemRef {
                    guard let currentItem = self.player?.currentItem,
                          ObjectIdentifier(currentItem) == observedItemRef
                    else { return }
                }
                completion?()
            }
        }
    }

    /// Remap the playing queue (and current track) after a library rescan
    /// so displayed metadata matches the store. Index and shuffle order
    /// are preserved; lookup is by standardized URL.
    func refreshTrackMetadata(using lookup: (URL) -> Track?) {
        queue.refreshTrackMetadata(using: lookup)
        currentQueue = queue.currentQueue
        currentIndex = queue.currentIndex
        currentTrack = queue.currentTrack
        if let track = currentTrack {
            duration = track.duration
            updateNowPlayingInfo()
        }
    }

    // MARK: - Shuffle Toggle

    func toggleShuffle() {
        queue.toggleShuffle(currentTrackID: currentTrack?.id)
        // Keep the published flag in sync without retriggering the didSet
        // (which would write back into `queue`).
        if shuffleEnabled != queue.shuffleEnabled {
            shuffleEnabled = queue.shuffleEnabled
        }
        Log.player.info("Shuffle: \(shuffleEnabled ? "on" : "off")")
        syncPublishedFromQueue()
    }

    func cycleRepeatMode() {
        queue.cycleRepeatMode()
        if repeatMode != queue.repeatMode {
            repeatMode = queue.repeatMode
        }
        Log.player.info("Repeat mode: \(repeatMode.rawValue)")
    }

    // MARK: - Action Dispatch

    private func apply(_ action: PlaybackQueue.Action) {
        switch action {
        case .load(let index):
            if let track = queue.currentQueue[safe: index] {
                loadAndPlay(track)
            }
        case .restart:
            seek(to: 0) { [weak self] in
                self?.play()
            }
        case .seekToZero:
            seek(to: 0)
        case .stop:
            isPlaying = false
            player?.pause()
            updateNowPlayingElapsed()
        case .noop:
            break
        }
    }

    private func syncPublishedFromQueue() {
        if currentQueue != queue.currentQueue { currentQueue = queue.currentQueue }
        if currentIndex != queue.currentIndex { currentIndex = queue.currentIndex }
    }

    /// Natural end-of-track. Goes through `queue.next()` so Repeat One
    /// restarts the same item instead of advancing.
    private func handleTrackDidPlayToEnd() {
        Log.player.debug("Track ended")
        let action = queue.next()
        syncPublishedFromQueue()
        apply(action)
    }

    private func handleLoadFailure() {
        consecutiveLoadFailures += 1
        let cap = min(5, max(currentQueue.count, 1))
        if consecutiveLoadFailures >= cap {
            Log.player.error("Stopping after \(consecutiveLoadFailures) consecutive load failures")
            consecutiveLoadFailures = 0
            apply(.stop)
            return
        }
        Log.player.debug("Auto-skip after load failure")
        let action = queue.skipForward()
        syncPublishedFromQueue()
        apply(action)
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

        activateAudioSession()

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
                    self.consecutiveLoadFailures = 0
                    self.play()
                    self.updateNowPlayingInfo()
                case .failed:
                    Log.player.error("AVPlayerItem failed: \(errorDescription)")
                    self.handleLoadFailure()
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
            Task { @MainActor in self?.handleTrackDidPlayToEnd() }
        }
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = CMTimeGetSeconds(time)
            // Already scheduled on `.main`; assign directly instead of
            // wrapping in another Task hop.
            MainActor.assumeIsolated {
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
                self.refreshNowPlayingProgressIfNeeded()
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
            MPMediaItemPropertyPlaybackDuration: duration > 0 ? duration : track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        if let image = ArtworkCache.cachedFullImage(for: track.url)
            ?? ArtworkCache.cachedThumbnail(for: track.url) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
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
                    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            }
        }
    }

    private func updateNowPlayingElapsed() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func refreshNowPlayingProgressIfNeeded() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastNowPlayingProgressWrite >= 1 else { return }
        lastNowPlayingProgressWrite = now
        updateNowPlayingElapsed()
    }
}

// MARK: - Safe Collection Access

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
