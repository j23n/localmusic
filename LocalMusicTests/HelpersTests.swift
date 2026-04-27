import Testing
@testable import LocalMusic

struct HelpersTests {

    // MARK: - Collection[safe:]

    @Test func safeSubscript_withinBounds() {
        let xs = [10, 20, 30]
        #expect(xs[safe: 0] == 10)
        #expect(xs[safe: 2] == 30)
    }

    @Test func safeSubscript_outOfBoundsReturnsNil() {
        let xs = [10, 20, 30]
        #expect(xs[safe: -1] == nil)
        #expect(xs[safe: 3] == nil)
        #expect(xs[safe: 999] == nil)
    }

    @Test func safeSubscript_emptyCollection() {
        let xs: [Int] = []
        #expect(xs[safe: 0] == nil)
    }

    // MARK: - SyncedLyricsView.activeIndex

    @Test @MainActor func activeIndex_emptyLinesReturnsZero() {
        #expect(SyncedLyricsView.activeIndex(in: [], at: 5.0) == 0)
    }

    @Test @MainActor func activeIndex_beforeFirstTimestampReturnsZero() {
        let lines = [
            SyncedLyricLine(timestamp: 1.0, text: "a"),
            SyncedLyricLine(timestamp: 2.0, text: "b")
        ]
        #expect(SyncedLyricsView.activeIndex(in: lines, at: 0.0) == 0)
    }

    @Test @MainActor func activeIndex_exactTimestampMatch() {
        let lines = [
            SyncedLyricLine(timestamp: 1.0, text: "a"),
            SyncedLyricLine(timestamp: 2.0, text: "b"),
            SyncedLyricLine(timestamp: 3.0, text: "c")
        ]
        #expect(SyncedLyricsView.activeIndex(in: lines, at: 2.0) == 1)
    }

    @Test @MainActor func activeIndex_betweenTimestamps() {
        let lines = [
            SyncedLyricLine(timestamp: 1.0, text: "a"),
            SyncedLyricLine(timestamp: 2.0, text: "b"),
            SyncedLyricLine(timestamp: 3.0, text: "c")
        ]
        #expect(SyncedLyricsView.activeIndex(in: lines, at: 2.5) == 1)
    }

    @Test @MainActor func activeIndex_afterLastReturnsLast() {
        let lines = [
            SyncedLyricLine(timestamp: 1.0, text: "a"),
            SyncedLyricLine(timestamp: 2.0, text: "b")
        ]
        #expect(SyncedLyricsView.activeIndex(in: lines, at: 99.0) == 1)
    }

    @Test @MainActor func activeIndex_monotonicAcrossSweep() {
        // Builds 100 lines at timestamps 0, 1, 2, …, 99 and sweeps `currentTime`
        // from -5 to 105 in 0.5-step increments. The result must be
        // non-decreasing.
        let lines = (0..<100).map {
            SyncedLyricLine(timestamp: Double($0), text: "L\($0)")
        }
        var lastIndex = SyncedLyricsView.activeIndex(in: lines, at: -5)
        var t = -5.0
        while t <= 105.0 {
            let idx = SyncedLyricsView.activeIndex(in: lines, at: t)
            #expect(idx >= lastIndex, "non-monotonic at t=\(t)")
            lastIndex = idx
            t += 0.5
        }
        #expect(lastIndex == 99)
    }

    @Test @MainActor func activeIndex_singleLine() {
        let lines = [SyncedLyricLine(timestamp: 5.0, text: "only")]
        #expect(SyncedLyricsView.activeIndex(in: lines, at: 0.0) == 0)
        #expect(SyncedLyricsView.activeIndex(in: lines, at: 5.0) == 0)
        #expect(SyncedLyricsView.activeIndex(in: lines, at: 100.0) == 0)
    }
}
