import XCTest
@testable import LocalMusic

final class PlaybackQueueTests: XCTestCase {

    // MARK: - play()

    func testPlay_shuffleOff_keepsOrderAndStartIndex() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(5)

        let action = q.play(track: tracks[2], queue: tracks, startIndex: 2)

        XCTAssertEqual(action, .load(2))
        XCTAssertEqual(q.currentQueue.map(\.id), tracks.map(\.id))
        XCTAssertEqual(q.currentIndex, 2)
        XCTAssertEqual(q.unshuffledQueue.map(\.id), tracks.map(\.id))
    }

    func testPlay_shuffleOn_pinsTrackAtIndexZero() {
        var q = PlaybackQueue()
        q.shuffleEnabled = true
        let tracks = Fixtures.tracks(5)

        let action = q.play(track: tracks[3], queue: tracks, startIndex: 3)

        XCTAssertEqual(action, .load(0))
        XCTAssertEqual(q.currentIndex, 0)
        XCTAssertEqual(q.currentQueue.first?.id, tracks[3].id)
        XCTAssertEqual(Set(q.currentQueue.map(\.id)), Set(tracks.map(\.id)))
        XCTAssertEqual(q.unshuffledQueue.map(\.id), tracks.map(\.id))
    }

    func testPlay_emptyQueue_returnsNoop() {
        var q = PlaybackQueue()
        let action = q.play(track: Fixtures.track(title: "lonely"), queue: [], startIndex: 0)
        XCTAssertEqual(action, .noop)
    }

    func testPlay_invalidStartIndex_returnsNoopRegardlessOfShuffle() {
        let tracks = Fixtures.tracks(3)

        var off = PlaybackQueue()
        XCTAssertEqual(off.play(track: tracks[0], queue: tracks, startIndex: 99), .noop)
        XCTAssertEqual(off.play(track: tracks[0], queue: tracks, startIndex: -1), .noop)
        XCTAssertTrue(off.currentQueue.isEmpty, "invalid input must not mutate state")

        var on = PlaybackQueue()
        on.shuffleEnabled = true
        XCTAssertEqual(on.play(track: tracks[0], queue: tracks, startIndex: 99), .noop)
        XCTAssertTrue(on.currentQueue.isEmpty)
    }

    // MARK: - setQueue()

    func testSetQueue_shuffleOff_keepsOrderAndStartIndex() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(4)

        let action = q.setQueue(tracks, startIndex: 2)

        XCTAssertEqual(action, .load(2))
        XCTAssertEqual(q.currentQueue.map(\.id), tracks.map(\.id))
        XCTAssertEqual(q.currentIndex, 2)
        XCTAssertEqual(q.unshuffledQueue.map(\.id), tracks.map(\.id))
    }

    func testSetQueue_invalidStartIndex_returnsNoop() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(3)
        XCTAssertEqual(q.setQueue(tracks, startIndex: 99), .noop)
        XCTAssertEqual(q.setQueue([], startIndex: 0), .noop)
    }

    func testSetQueue_shuffleOn_movesStartTrackToHead() {
        var q = PlaybackQueue()
        q.shuffleEnabled = true
        let tracks = Fixtures.tracks(4)

        let action = q.setQueue(tracks, startIndex: 2)

        XCTAssertEqual(action, .load(0))
        XCTAssertEqual(q.currentQueue.first?.id, tracks[2].id)
        XCTAssertEqual(Set(q.currentQueue.map(\.id)), Set(tracks.map(\.id)))
    }

    // MARK: - next()

    func testNext_advancesIndex() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[0], queue: tracks, startIndex: 0)

        XCTAssertEqual(q.next(), .load(1))
        XCTAssertEqual(q.currentIndex, 1)
    }

    func testNext_atEndWithRepeatOff_stops() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[2], queue: tracks, startIndex: 2)

        XCTAssertEqual(q.next(), .stop)
        XCTAssertEqual(q.currentIndex, 2, "index should not advance past the end")
    }

    func testNext_atEndWithRepeatAll_wrapsToZero() {
        var q = PlaybackQueue()
        q.repeatMode = .all
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[2], queue: tracks, startIndex: 2)

        XCTAssertEqual(q.next(), .load(0))
        XCTAssertEqual(q.currentIndex, 0)
    }

    func testNext_repeatOne_returnsRestart() {
        var q = PlaybackQueue()
        q.repeatMode = .one
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[1], queue: tracks, startIndex: 1)

        XCTAssertEqual(q.next(), .restart)
        XCTAssertEqual(q.currentIndex, 1, "repeat .one must not advance the index")
    }

    func testNext_emptyQueue_returnsNoop() {
        var q = PlaybackQueue()
        XCTAssertEqual(q.next(), .noop)
    }

    // MARK: - previous()

    func testPrevious_pastThreeSeconds_returnsSeekToZeroWithoutMovingIndex() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[1], queue: tracks, startIndex: 1)

        XCTAssertEqual(q.previous(currentTime: 5.0), .seekToZero)
        XCTAssertEqual(q.currentIndex, 1)
    }

    func testPrevious_atThreeSecondsExactly_movesToPrevTrack() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[1], queue: tracks, startIndex: 1)

        // The boundary uses `> 3` strictly, so exactly 3.0 should NOT seek.
        XCTAssertEqual(q.previous(currentTime: 3.0), .load(0))
        XCTAssertEqual(q.currentIndex, 0)
    }

    func testPrevious_normal_decrementsIndex() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[2], queue: tracks, startIndex: 2)

        XCTAssertEqual(q.previous(currentTime: 0), .load(1))
        XCTAssertEqual(q.currentIndex, 1)
    }

    func testPrevious_atHeadWithRepeatAll_wrapsToLast() {
        var q = PlaybackQueue()
        q.repeatMode = .all
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[0], queue: tracks, startIndex: 0)

        XCTAssertEqual(q.previous(currentTime: 0), .load(2))
        XCTAssertEqual(q.currentIndex, 2)
    }

    func testPrevious_atHeadWithRepeatOff_returnsSeekToZero() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[0], queue: tracks, startIndex: 0)

        XCTAssertEqual(q.previous(currentTime: 0), .seekToZero)
        XCTAssertEqual(q.currentIndex, 0)
    }

    func testPrevious_emptyQueue_returnsNoop() {
        var q = PlaybackQueue()
        XCTAssertEqual(q.previous(currentTime: 0), .noop)
    }

    // MARK: - toggleShuffle()

    func testToggleShuffle_on_pinsCurrentAndPreservesOriginal() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(5)
        _ = q.play(track: tracks[2], queue: tracks, startIndex: 2)
        let currentID = q.currentTrack?.id

        q.toggleShuffle(currentTrackID: currentID)

        XCTAssertTrue(q.shuffleEnabled)
        XCTAssertEqual(q.currentIndex, 0)
        XCTAssertEqual(q.currentTrack?.id, tracks[2].id)
        XCTAssertEqual(Set(q.currentQueue.map(\.id)), Set(tracks.map(\.id)))
        XCTAssertEqual(q.unshuffledQueue.map(\.id), tracks.map(\.id))
    }

    func testToggleShuffle_off_restoresOriginalOrderAndIndex() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(5)
        _ = q.play(track: tracks[2], queue: tracks, startIndex: 2)
        // turn on, then off
        q.toggleShuffle(currentTrackID: q.currentTrack?.id)
        let currentID = q.currentTrack?.id

        q.toggleShuffle(currentTrackID: currentID)

        XCTAssertFalse(q.shuffleEnabled)
        XCTAssertEqual(q.currentQueue.map(\.id), tracks.map(\.id))
        XCTAssertEqual(q.currentIndex, 2)
    }

    func testToggleShuffle_emptyQueue_justFlipsFlag() {
        var q = PlaybackQueue()
        q.toggleShuffle(currentTrackID: nil)
        XCTAssertTrue(q.shuffleEnabled)
        XCTAssertTrue(q.currentQueue.isEmpty)
    }

    // MARK: - cycleRepeatMode()

    func testCycleRepeatMode_offAllOneOff() {
        var q = PlaybackQueue()
        XCTAssertEqual(q.repeatMode, .off)
        q.cycleRepeatMode(); XCTAssertEqual(q.repeatMode, .all)
        q.cycleRepeatMode(); XCTAssertEqual(q.repeatMode, .one)
        q.cycleRepeatMode(); XCTAssertEqual(q.repeatMode, .off)
    }
}
