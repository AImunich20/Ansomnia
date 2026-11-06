import CoreGraphics
import XCTest
@testable import Ansomnia

/// The × in the status item ends the session on one click, taken in a local
/// event monitor before the status bar button or SwiftUI can claim it.
final class EndClickTrackerTests: XCTestCase {
    private let button = CGRect(x: 80, y: 1, width: 20, height: 20)
    private let none = EndClickTracker.Result(swallow: false, pressed: nil, end: false)

    /// The session ends on the press itself: a click the menu bar forwards
    /// may never bring its mouse-up. The rest of the click is swallowed.
    func testAPressOnTheButtonEndsTheSessionAtOnceAndTheClickIsSwallowedWhole() {
        var tracker = EndClickTracker()
        XCTAssertEqual(tracker.handle(.down, at: CGPoint(x: 90, y: 11), endButton: button),
                       .init(swallow: true, pressed: true, end: true))
        XCTAssertTrue(tracker.isTracking)
        XCTAssertEqual(tracker.handle(.dragged, at: CGPoint(x: 10, y: 11), endButton: nil),
                       .init(swallow: true, pressed: nil, end: false))
        XCTAssertEqual(tracker.handle(.up, at: CGPoint(x: 10, y: 11), endButton: nil),
                       .init(swallow: true, pressed: false, end: false), "ends once, not again on release")
        XCTAssertFalse(tracker.isTracking)
    }

    /// macOS 26 hands the app a status item click at the item's centre, so
    /// the point can miss the × the pointer is on. Its hover is trusted.
    func testHoveringTheButtonCountsAsAHitWhereverTheClickLands() {
        var tracker = EndClickTracker()
        XCTAssertEqual(tracker.handle(.down, at: CGPoint(x: 59, y: 11), endButton: button, hovering: true),
                       .init(swallow: true, pressed: true, end: true))
    }

    func testAClickElsewhereIsLeftToTheRestOfTheApp() {
        var tracker = EndClickTracker()
        for point in [CGPoint(x: 10, y: 11), CGPoint(x: 60, y: 11)] {
            XCTAssertEqual(tracker.handle(.down, at: point, endButton: button), none)
            XCTAssertEqual(tracker.handle(.dragged, at: CGPoint(x: 90, y: 11), endButton: button), none)
            XCTAssertEqual(tracker.handle(.up, at: CGPoint(x: 90, y: 11), endButton: button), none,
                           "a press that began off the × does not end on it")
        }
    }

    func testNoButtonMeansNoClickIsTakenEvenWhenHovering() {
        var tracker = EndClickTracker()
        XCTAssertEqual(tracker.handle(.down, at: CGPoint(x: 90, y: 11), endButton: nil, hovering: true), none)
        XCTAssertFalse(tracker.isTracking)
    }

    /// The fallback: the × is the bar's last 20 points before its 6 point
    /// trailing inset, the full height of the bar.
    @MainActor
    func testTheLayoutPutsTheButtonAtTheTrailingEndOfTheBar() {
        let frame = StatusItemController.endButtonLayoutFrame(barWidth: 120, height: 22)
        XCTAssertEqual(frame, CGRect(x: 94, y: 0, width: 20, height: 22))
    }
}
