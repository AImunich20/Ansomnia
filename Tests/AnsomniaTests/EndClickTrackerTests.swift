import CoreGraphics
import XCTest
@testable import Ansomnia

/// The × in the status item ends the session on one click, taken in a local
/// event monitor before the status bar button or SwiftUI can claim it.
final class EndClickTrackerTests: XCTestCase {
    private let button = CGRect(x: 80, y: 1, width: 20, height: 20)

    func testAClickOnTheButtonEndsTheSessionAndIsSwallowedWhole() {
        var tracker = EndClickTracker()
        let down = tracker.handle(.down, at: CGPoint(x: 90, y: 11), endButton: button)
        XCTAssertEqual(down, .init(swallow: true, pressed: true, end: false))
        XCTAssertTrue(tracker.isTracking)
        let up = tracker.handle(.up, at: CGPoint(x: 91, y: 12), endButton: button)
        XCTAssertEqual(up, .init(swallow: true, pressed: false, end: true))
        XCTAssertFalse(tracker.isTracking)
    }

    func testAClickElsewhereIsLeftToTheRestOfTheApp() {
        var tracker = EndClickTracker()
        for point in [CGPoint(x: 10, y: 11), CGPoint(x: 60, y: 11)] {
            XCTAssertEqual(tracker.handle(.down, at: point, endButton: button), .init(swallow: false, pressed: nil, end: false))
            XCTAssertEqual(tracker.handle(.dragged, at: point, endButton: button), .init(swallow: false, pressed: nil, end: false))
            XCTAssertEqual(tracker.handle(.up, at: CGPoint(x: 90, y: 11), endButton: button), .init(swallow: false, pressed: nil, end: false),
                           "a press that began off the × does not end on it")
        }
    }

    func testNoButtonMeansNoClickIsTaken() {
        var tracker = EndClickTracker()
        XCTAssertEqual(tracker.handle(.down, at: CGPoint(x: 90, y: 11), endButton: nil), .init(swallow: false, pressed: nil, end: false))
        XCTAssertFalse(tracker.isTracking)
    }

    func testDraggingAwayCancelsAndComingBackRestores() {
        var tracker = EndClickTracker()
        _ = tracker.handle(.down, at: CGPoint(x: 90, y: 11), endButton: button)
        let near = CGPoint(x: button.maxX + EndClickTracker.cancelDistance - 1, y: 11)
        let far = CGPoint(x: button.maxX + EndClickTracker.cancelDistance + 5, y: 11)
        XCTAssertEqual(tracker.handle(.dragged, at: near, endButton: button), .init(swallow: true, pressed: true, end: false), "within the slop")
        XCTAssertEqual(tracker.handle(.dragged, at: far, endButton: button), .init(swallow: true, pressed: false, end: false))
        XCTAssertEqual(tracker.handle(.up, at: far, endButton: button), .init(swallow: true, pressed: false, end: false), "released away: cancelled")

        _ = tracker.handle(.down, at: CGPoint(x: 90, y: 11), endButton: button)
        _ = tracker.handle(.dragged, at: far, endButton: button)
        XCTAssertEqual(tracker.handle(.up, at: near, endButton: button), .init(swallow: true, pressed: false, end: true), "back over it: ends")
    }

    /// The press is judged against the frame it began on, so a relayout
    /// during the click does not move the target under the pointer.
    func testTheFrameIsTheOneThePressBeganOn() {
        var tracker = EndClickTracker()
        _ = tracker.handle(.down, at: CGPoint(x: 90, y: 11), endButton: button)
        XCTAssertEqual(tracker.handle(.up, at: CGPoint(x: 90, y: 11), endButton: nil), .init(swallow: true, pressed: false, end: true))
    }

    /// The fallback: the × is the bar's last 20 points before its 6 point
    /// trailing inset, the full height of the bar.
    @MainActor
    func testTheLayoutPutsTheButtonAtTheTrailingEndOfTheBar() {
        let frame = StatusItemController.endButtonLayoutFrame(barWidth: 120, height: 22)
        XCTAssertEqual(frame, CGRect(x: 94, y: 0, width: 20, height: 22))
    }
}
