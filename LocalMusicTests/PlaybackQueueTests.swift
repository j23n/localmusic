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

    // MARK: - skipForward()

    @Test func skipForward_advancesIndex() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[0], queue: tracks, startIndex: 0)

        #expect(q.skipForward() == .load(1))
        #expect(q.currentIndex == 1)
    }

    @Test func skipForward_repeatOne_advancesIndex() {
        var q = PlaybackQueue()
        q.repeatMode = .one
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[1], queue: tracks, startIndex: 1)

        #expect(q.skipForward() == .load(2))
        #expect(q.currentIndex == 2, "user-initiated next must leave the current track")
    }

    @Test func skipForward_repeatOne_fromFirstTrack_advancesToSecond() {
        var q = PlaybackQueue()
        q.repeatMode = .one
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[0], queue: tracks, startIndex: 0)

        #expect(q.skipForward() == .load(1))
        #expect(q.currentIndex == 1)
        #expect(q.currentTrack?.id == tracks[1].id)
    }

    @Test func skipForward_repeatOne_atEnd_stopsWithoutWrapping() {
        var q = PlaybackQueue()
        q.repeatMode = .one
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[2], queue: tracks, startIndex: 2)

        #expect(q.skipForward() == .stop)
        #expect(q.currentIndex == 2, "index should not advance past the end")
    }

    @Test func skipForward_repeatOne_doesNotRestartUnlikeNaturalNext() {
        var q = PlaybackQueue()
        q.repeatMode = .one
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[1], queue: tracks, startIndex: 1)

        #expect(q.next() == .restart)
        #expect(q.currentIndex == 1)

        #expect(q.skipForward() == .load(2))
        #expect(q.currentIndex == 2)
    }

    @Test func skipForward_atEndWithRepeatOff_stops() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[2], queue: tracks, startIndex: 2)

        #expect(q.skipForward() == .stop)
        #expect(q.currentIndex == 2)
    }

    @Test func skipForward_atEndWithRepeatAll_wrapsToZero() {
        var q = PlaybackQueue()
        q.repeatMode = .all
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[2], queue: tracks, startIndex: 2)

        #expect(q.skipForward() == .load(0))
        #expect(q.currentIndex == 0)
    }

    @Test func skipForward_repeatAll_fromMiddle_advances() {
        var q = PlaybackQueue()
        q.repeatMode = .all
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[0], queue: tracks, startIndex: 0)

        #expect(q.skipForward() == .load(1))
        #expect(q.currentIndex == 1)
    }

    @Test func skipForward_singleTrackRepeatOne_stopsAtEnd() {
        var q = PlaybackQueue()
        q.repeatMode = .one
        let tracks = Fixtures.tracks(1)
        _ = q.play(track: tracks[0], queue: tracks, startIndex: 0)

        #expect(q.skipForward() == .stop)
        #expect(q.currentIndex == 0)
        #expect(q.next() == .restart, "natural end still restarts the lone track")
    }

    @Test func skipForward_emptyQueue_returnsNoop() {
        var q = PlaybackQueue()
        q.repeatMode = .one
        #expect(q.skipForward() == .noop)
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

    // MARK: - refreshTrackMetadata()

    @Test func refreshTrackMetadata_updatesFieldsPreservingIndexAndOrder() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(3)
        _ = q.play(track: tracks[1], queue: tracks, startIndex: 1)

        let updated = Track(
            id: tracks[1].id,
            url: tracks[1].url,
            title: "Retitled",
            artist: "New Artist",
            album: "New Album",
            duration: 240,
            hasArtwork: true,
            hasLyrics: true
        )

        q.refreshTrackMetadata { url in
            url.standardized == tracks[1].url.standardized ? updated : nil
        }

        #expect(q.currentIndex == 1)
        #expect(q.currentQueue.map(\.id) == tracks.map(\.id))
        #expect(q.currentQueue[1].title == "Retitled")
        #expect(q.currentQueue[1].artist == "New Artist")
        #expect(q.currentQueue[1].album == "New Album")
        #expect(q.currentQueue[1].duration == 240)
        #expect(q.currentQueue[1].hasArtwork)
        #expect(q.currentQueue[1].hasLyrics)
        #expect(q.unshuffledQueue[1].title == "Retitled")
        #expect(q.currentTrack?.title == "Retitled")
        #expect(q.currentQueue[0].title == tracks[0].title, "unmatched tracks stay as-is")
    }

    @Test func refreshTrackMetadata_matchesStandardizedURLs() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(2)
        _ = q.play(track: tracks[0], queue: tracks, startIndex: 0)

        let dotted = URL(fileURLWithPath: "/fixtures/./track-0.mp3")
        let updated = Track(
            id: tracks[0].id,
            url: tracks[0].url,
            title: "From Dotted Path",
            artist: tracks[0].artist,
            album: tracks[0].album,
            duration: tracks[0].duration,
            hasArtwork: false,
            hasLyrics: false
        )

        q.refreshTrackMetadata { url in
            url.standardized.path == dotted.standardized.path ? updated : nil
        }

        #expect(q.currentQueue[0].title == "From Dotted Path")
    }

    @Test func refreshTrackMetadata_preservesShuffleLayout() {
        var q = PlaybackQueue()
        q.shuffleEnabled = true
        let tracks = Fixtures.tracks(5)
        _ = q.play(track: tracks[3], queue: tracks, startIndex: 3)
        let orderBefore = q.currentQueue.map(\.id)
        let unshuffledBefore = q.unshuffledQueue.map(\.id)
        let indexBefore = q.currentIndex

        let byURL = Dictionary(uniqueKeysWithValues: tracks.map { track in
            let refreshed = Track(
                id: track.id,
                url: track.url,
                title: "Updated \(track.title)",
                artist: track.artist,
                album: track.album,
                duration: track.duration,
                hasArtwork: false,
                hasLyrics: false
            )
            return (track.url.standardized, refreshed)
        })

        q.refreshTrackMetadata { byURL[$0.standardized] }

        #expect(q.currentIndex == indexBefore)
        #expect(q.currentQueue.map(\.id) == orderBefore)
        #expect(q.unshuffledQueue.map(\.id) == unshuffledBefore)
        #expect(q.currentQueue.map(\.title) == orderBefore.map { id in
            "Updated \(tracks.first { $0.id == id }!.title)"
        })
        #expect(q.unshuffledQueue.map(\.title) == ["Updated T0", "Updated T1", "Updated T2", "Updated T3", "Updated T4"])
        #expect(q.shuffleEnabled)
    }

    @Test func refreshTrackMetadata_emptyLookupLeavesQueueUnchanged() {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(2)
        _ = q.play(track: tracks[0], queue: tracks, startIndex: 0)

        q.refreshTrackMetadata { _ in nil }

        #expect(q.currentQueue.map(\.id) == tracks.map(\.id))
        #expect(q.currentQueue.map(\.title) == tracks.map(\.title))
        #expect(q.currentIndex == 0)
    }
}
