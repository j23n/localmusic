import Foundation

/// Pure value-type state machine for the playback queue: track ordering,
/// shuffle, and repeat. Kept free of `AVPlayer` so the logic can be unit
/// tested without playing audio. `AudioPlayerManager` owns one of these,
/// applies mutations, and translates the returned `Action` into AVFoundation
/// calls.
struct PlaybackQueue: Equatable {

    // MARK: - State

    var currentQueue: [Track] = []
    var currentIndex: Int = 0
    var unshuffledQueue: [Track] = []
    var repeatMode: RepeatMode = .off
    var shuffleEnabled: Bool = false

    // MARK: - Actions returned to the caller

    /// What the host should do after a queue mutation. Decoupling lets us
    /// verify behaviour in tests without an `AVPlayer` instance.
    enum Action: Equatable {
        /// Load and play the track at `currentIndex`.
        case load(Int)
        /// Restart the current item from 0 and force playback (next with
        /// `.one` repeat). Distinct from `.seekToZero` which preserves the
        /// play/pause state.
        case restart
        /// Seek the existing item back to 0 without changing play/pause
        /// state. Used by `previous()` when `currentTime > 3` or when at the
        /// head of a non-repeating queue.
        case seekToZero
        /// End of queue with no repeat — pause and stop advancing.
        case stop
        /// Nothing to do (queue was empty, etc.).
        case noop
    }

    // MARK: - Mutations

    /// Begin playback of `track` from a fresh `queue`. With shuffle enabled,
    /// the played track is pinned at index 0 and the rest of the queue is
    /// shuffled around it. Returns `.noop` on an invalid `startIndex` so the
    /// caller's `track` is never silently swapped for a different element.
    mutating func play(track: Track, queue: [Track], startIndex: Int) -> Action {
        guard queue.indices.contains(startIndex) else { return .noop }
        unshuffledQueue = queue
        if shuffleEnabled {
            var shuffled = queue
            shuffled.remove(at: startIndex)
            shuffled.shuffle()
            shuffled.insert(track, at: 0)
            currentQueue = shuffled
            currentIndex = 0
        } else {
            currentQueue = queue
            currentIndex = startIndex
        }
        return .load(currentIndex)
    }

    /// Replace the queue without specifying the "current" track separately.
    /// The track at `startIndex` becomes the head when shuffling.
    mutating func setQueue(_ tracks: [Track], startIndex: Int) -> Action {
        guard tracks.indices.contains(startIndex) else { return .noop }
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
        return .load(currentIndex)
    }

    mutating func next() -> Action {
        guard !currentQueue.isEmpty else { return .noop }
        if repeatMode == .one { return .restart }

        let nextIndex = currentIndex + 1
        if nextIndex < currentQueue.count {
            currentIndex = nextIndex
            return .load(currentIndex)
        }
        if repeatMode == .all {
            currentIndex = 0
            return .load(0)
        }
        return .stop
    }

    mutating func previous(currentTime: Double) -> Action {
        guard !currentQueue.isEmpty else { return .noop }
        if currentTime > 3 { return .seekToZero }

        let prevIndex = currentIndex - 1
        if prevIndex >= 0 {
            currentIndex = prevIndex
            return .load(currentIndex)
        }
        if repeatMode == .all {
            currentIndex = currentQueue.count - 1
            return .load(currentIndex)
        }
        return .seekToZero
    }

    /// Toggle the shuffle flag. When turning shuffle on, the supplied
    /// `currentTrackID` (if present in the queue) is pinned at index 0 so the
    /// listener doesn't experience an abrupt track change.
    mutating func toggleShuffle(currentTrackID: UUID?) {
        shuffleEnabled.toggle()
        guard !currentQueue.isEmpty,
              let id = currentTrackID,
              let current = currentQueue.first(where: { $0.id == id })
        else { return }

        if shuffleEnabled {
            unshuffledQueue = currentQueue
            var shuffled = currentQueue.filter { $0.id != id }
            shuffled.shuffle()
            shuffled.insert(current, at: 0)
            currentQueue = shuffled
            currentIndex = 0
        } else if let idx = unshuffledQueue.firstIndex(where: { $0.id == id }) {
            currentQueue = unshuffledQueue
            currentIndex = idx
        }
    }

    mutating func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    // MARK: - Lookups

    var currentTrack: Track? {
        currentQueue.indices.contains(currentIndex) ? currentQueue[currentIndex] : nil
    }
}
