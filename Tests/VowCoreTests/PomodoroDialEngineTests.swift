import XCTest
@testable import VowCore

final class PomodoroDialEngineTests: XCTestCase {
    func test_idle_to_running_focus_onSpunToStart() {
        var engine = PomodoroDialEngine(focusDurationSeconds: 10, restDurationSeconds: 5)
        let analytics = engine.handle(.spunToStart)

        XCTAssertEqual(engine.state.status, .running)
        XCTAssertEqual(engine.state.segment, .focus)
        XCTAssertEqual(engine.state.remainingSeconds, 10)
        XCTAssertTrue(analytics.isEmpty)
    }

    func test_pause_prevents_tick() {
        var engine = PomodoroDialEngine(focusDurationSeconds: 10, restDurationSeconds: 5)
        _ = engine.handle(.spunToStart)
        _ = engine.handle(.pauseTapped)
        XCTAssertEqual(engine.state.status, .paused)

        _ = engine.handle(.ticked(seconds: 3))
        XCTAssertEqual(engine.state.remainingSeconds, 10)
        XCTAssertEqual(engine.state.status, .paused)
    }

    func test_complete_focus_then_rest_then_completed() {
        var engine = PomodoroDialEngine(focusDurationSeconds: 2, restDurationSeconds: 1)
        var analytics: [PomodoroDialAnalyticsEvent] = []

        _ = engine.handle(.spunToStart)
        XCTAssertEqual(engine.state.status, .running)
        XCTAssertEqual(engine.state.segment, .focus)

        analytics = engine.handle(.ticked(seconds: 2))
        XCTAssertEqual(engine.state.status, .running)
        XCTAssertEqual(engine.state.segment, .rest)
        XCTAssertEqual(engine.state.remainingSeconds, 1)
        XCTAssertEqual(analytics, [.segmentCompleted(.focus)])

        analytics = engine.handle(.ticked(seconds: 1))
        XCTAssertEqual(engine.state.status, .completed)
        XCTAssertNil(engine.state.segment)
        XCTAssertEqual(engine.state.remainingSeconds, 0)
        XCTAssertEqual(analytics, [.segmentCompleted(.rest), .sessionCompleted])
    }

    func test_skip_advances_segment_even_when_paused() {
        var engine = PomodoroDialEngine(focusDurationSeconds: 10, restDurationSeconds: 5)
        _ = engine.handle(.spunToStart)
        _ = engine.handle(.pauseTapped)

        let analytics = engine.handle(.skipTapped)
        XCTAssertEqual(engine.state.status, .running)
        XCTAssertEqual(engine.state.segment, .rest)
        XCTAssertEqual(engine.state.remainingSeconds, 5)
        XCTAssertEqual(analytics, [.segmentCompleted(.focus)])
    }
}
