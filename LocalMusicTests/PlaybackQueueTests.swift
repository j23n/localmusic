import Testing
@testable import LocalMusic

struct PlaybackQueueTests {

    // MARK: - play()

    @Test func play_shuffleOff_keepsOrderAndStartIndex() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(5)

        let action = q.play(track: tracks[2], queue: tracks, startIndex: 2)

        #expect(action == .load(2))
        #expect(q.currentQueue.map(\.id) == tracks.map(\.id))
        #expect(q.currentIndex == 2)
        #expect(q.unshuffledQueue.map(\.id) == tracks.map(\.id))
    }

    @Test func play_shuffleOn_pinsTrackAtIndexZero() {
        var q = PlaybackQueue()
        q.shuffleEnabled = true
        let tracks = Fixtures.tracks(5)

        let action = q.play(track: tracks[3], queue: tracks, startIndex: 3)

        #expect(action == .load(0))
        #expect(q.currentIndex == 0)
        #expect(q.currentQueue.first?.id == tracks[3].id)
        #expect(Set(q.currentQueue.map(\.id)) == Set(tracks.map(\.id)))
        #expect(q.unshuffledQueue.map(\.id) == tracks.map(\.id))
    }

    @Test func play_emptyQueue_returnsNoop() {
        var q = PlaybackQueue()
        let action = q.play(track: Fixtures.track(title: "lonely"), queue: [], startIndex: 0)
        #expect(action == .noop)
    }

    @Test func play_invalidStartIndex_returnsNoopRegardlessOfShuffle() {
        let tracks = Fixtures.tracks(3)

        var off = PlaybackQueue()
        #expect(off.play(track: tracks[0], queue: tracks, startIndex: 99) == .noop)
        #expect(off.play(track: tracks[0], queue: tracks, startIndex: -1) == .noop)
        #expect(off.currentQueue.isEmpty, "invalid input must not mutate state")

        var on = PlaybackQueue()
        on.shuffleEnabled = true
        #expect(on.play(track: tracks[0], queue: tracks, startIndex: 99) == .noop)
        #expect(on.currentQueue.isEmpty)
    }

    // MARK: - setQueue()

    @Test func setQueue_shuffleOff_keepsOrderAndStartIndex() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(4)

        let action = q.setQueue(tracks, startIndex: 2)

        #expect(action == .load(2))
        #expect(q.currentQueue.map(\.id) == tracks.map(\.id))
        #expect(q.currentIndex == 2)
        #expect(q.unshuffledQueue.map(\.id) == tracks.map(\.id))
    }

    @Test func setQueue_invalidStartIndex_returnsNoop() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(3)
        #expect(q.setQueue(tracks, startIndex: 99) == .noop)
        #expect(q.setQueue([], startIndex: 0) == .noop)
    }

    @Test func setQueue_shuffleOn_movesStartTrackToHead() {
        var q = PlaybackQueue()
        q.shuffleEnabled = true
        let tracks = Fixtures.tracks(4)

        let action = q.setQueue(tracks, startIndex: 2)

        #expect(action == .load(0))
        #expect(q.currentQueue.first?.id == tracks[2].id)
        #expect(Set(q.currentQueue.map(\.id)) == Set(tracks.map(\.id)))
    }

    // MARK: - next()

    @Test func next_advancesIndex() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[0], queue: tracks, startIndex: 0)

        #expect(q.next() == .load(1))
        #expect(q.currentIndex == 1)
    }

    @Test func next_atEndWithRepeatOff_stops() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[2], queue: tracks, startIndex: 2)

        #expect(q.next() == .stop)
        #expect(q.currentIndex == 2, "index should not advance past the end")
    }

    @Test func next_atEndWithRepeatAll_wrapsToZero() {
        var q = PlaybackQueue()
        q.repeatMode = .all
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[2], queue: tracks, startIndex: 2)

        #expect(q.next() == .load(0))
        #expect(q.currentIndex == 0)
    }

    @Test func next_repeatOne_returnsRestart() {
        var q = PlaybackQueue()
        q.repeatMode = .one
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[1], queue: tracks, startIndex: 1)

        #expect(q.next() == .restart)
        #expect(q.currentIndex == 1, "repeat .one must not advance the index")
    }

    @Test func next_emptyQueue_returnsNoop() {
        var q = PlaybackQueue()
        #expect(q.next() == .noop)
    }

    // MARK: - previous()

    @Test func previous_pastThreeSeconds_returnsSeekToZeroWithoutMovingIndex() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[1], queue: tracks, startIndex: 1)

        #expect(q.previous(currentTime: 5.0) == .seekToZero)
        #expect(q.currentIndex == 1)
    }

    @Test func previous_atThreeSecondsExactly_movesToPrevTrack() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[1], queue: tracks, startIndex: 1)

        // The boundary uses `> 3` strictly, so exactly 3.0 should NOT seek.
        #expect(q.previous(currentTime: 3.0) == .load(0))
        #expect(q.currentIndex == 0)
    }

    @Test func previous_normal_decrementsIndex() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[2], queue: tracks, startIndex: 2)

        #expect(q.previous(currentTime: 0) == .load(1))
        #expect(q.currentIndex == 1)
    }

    @Test func previous_atHeadWithRepeatAll_wrapsToLast() {
        var q = PlaybackQueue()
        q.repeatMode = .all
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[0], queue: tracks, startIndex: 0)

        #expect(q.previous(currentTime: 0) == .load(2))
        #expect(q.currentIndex == 2)
    }

    @Test func previous_atHeadWithRepeatOff_returnsSeekToZero() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[0], queue: tracks, startIndex: 0)

        #expect(q.previous(currentTime: 0) == .seekToZero)
        #expect(q.currentIndex == 0)
    }

    @Test func previous_emptyQueue_returnsNoop() {
        var q = PlaybackQueue()
        #expect(q.previous(currentTime: 0) == .noop)
    }

    // MARK: - toggleShuffle()

    @Test func toggleShuffle_on_pinsCurrentAndPreservesOriginal() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(5)
        _ = q.play(track: tracks[2], queue: tracks, startIndex: 2)
        let currentID = q.currentTrack?.id

        q.toggleShuffle(currentTrackID: currentID)

        #expect(q.shuffleEnabled)
        #expect(q.currentIndex == 0)
        #expect(q.currentTrack?.id == tracks[2].id)
        #expect(Set(q.currentQueue.map(\.id)) == Set(tracks.map(\.id)))
        #expect(q.unshuffledQueue.map(\.id) == tracks.map(\.id))
    }

    @Test func toggleShuffle_off_restoresOriginalOrderAndIndex() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(5)
        _ = q.play(track: tracks[2], queue: tracks, startIndex: 2)
        // turn on, then off
        q.toggleShuffle(currentTrackID: q.currentTrack?.id)
        let currentID = q.currentTrack?.id

        q.toggleShuffle(currentTrackID: currentID)

        #expect(!q.shuffleEnabled)
        #expect(q.currentQueue.map(\.id) == tracks.map(\.id))
        #expect(q.currentIndex == 2)
    }

    @Test func toggleShuffle_emptyQueue_justFlipsFlag() {
        var q = PlaybackQueue()
        q.toggleShuffle(currentTrackID: nil)
        #expect(q.shuffleEnabled)
        #expect(q.currentQueue.isEmpty)
    }

    // MARK: - cycleRepeatMode()

    @Test func cycleRepeatMode_offAllOneOff() {
        var q = PlaybackQueue()
        #expect(q.repeatMode == .off)
        q.cycleRepeatMode(); #expect(q.repeatMode == .all)
        q.cycleRepeatMode(); #expect(q.repeatMode == .one)
        q.cycleRepeatMode(); #expect(q.repeatMode == .off)
    }
}
