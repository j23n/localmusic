import XCTest
@testable import LocalMusic

final class HelpersTests: XCTestCase {

    // MARK: - Collection[safe:]

    func testSafeSubscript_withinBounds() {
        let xs = [10, 20, 30]
        XCTAssertEqual(xs[safe: 0], 10)
        XCTAssertEqual(xs[safe: 2], 30)
    }

    func testSafeSubscript_outOfBoundsReturnsNil() {
        let xs = [10, 20, 30]
        XCTAssertNil(xs[safe: -1])
        XCTAssertNil(xs[safe: 3])
        XCTAssertNil(xs[safe: 999])
    }

    func testSafeSubscript_emptyCollection() {
        let xs: [Int] = []
        XCTAssertNil(xs[safe: 0])
    }

    // MARK: - SyncedLyricsView.activeIndex

    func testActiveIndex_emptyLinesReturnsZero() {
        XCTAssertEqual(SyncedLyricsView.activeIndex(in: [], at: 5.0), 0)
    }

    func testActiveIndex_beforeFirstTimestampReturnsZero() {
        let lines = [
            SyncedLyricLine(timestamp: 1.0, text: "a"),
            SyncedLyricLine(timestamp: 2.0, text: "b")
        ]
        XCTAssertEqual(SyncedLyricsView.activeIndex(in: lines, at: 0.0), 0)
    }

    func testActiveIndex_exactTimestampMatch() {
        let lines = [
            SyncedLyricLine(timestamp: 1.0, text: "a"),
            SyncedLyricLine(timestamp: 2.0, text: "b"),
            SyncedLyricLine(timestamp: 3.0, text: "c")
        ]
        XCTAssertEqual(SyncedLyricsView.activeIndex(in: lines, at: 2.0), 1)
    }

    func testActiveIndex_betweenTimestamps() {
        let lines = [
            SyncedLyricLine(timestamp: 1.0, text: "a"),
            SyncedLyricLine(timestamp: 2.0, text: "b"),
            SyncedLyricLine(timestamp: 3.0, text: "c")
        ]
        XCTAssertEqual(SyncedLyricsView.activeIndex(in: lines, at: 2.5), 1)
    }

    func testActiveIndex_afterLastReturnsLast() {
        let lines = [
            SyncedLyricLine(timestamp: 1.0, text: "a"),
            SyncedLyricLine(timestamp: 2.0, text: "b")
        ]
        XCTAssertEqual(SyncedLyricsView.activeIndex(in: lines, at: 99.0), 1)
    }

    func testActiveIndex_monotonicAcrossSweep() {
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
            XCTAssertGreaterThanOrEqual(idx, lastIndex, "non-monotonic at t=\(t)")
            lastIndex = idx
            t += 0.5
        }
        XCTAssertEqual(lastIndex, 99)
    }

    func testActiveIndex_singleLine() {
        let lines = [SyncedLyricLine(timestamp: 5.0, text: "only")]
        XCTAssertEqual(SyncedLyricsView.activeIndex(in: lines, at: 0.0), 0)
        XCTAssertEqual(SyncedLyricsView.activeIndex(in: lines, at: 5.0), 0)
        XCTAssertEqual(SyncedLyricsView.activeIndex(in: lines, at: 100.0), 0)
    }
}
