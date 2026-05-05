import XCTest
@testable import VowCore

final class LifeTrackerEngineTests: XCTestCase {
    func test_pointsConversion_movement_focus_journal() {
        let engine = LifeTrackerEngine(pointPolicy: .init(movementStepsPerPoint: 250, focusSecondsPerPoint: 900, journalCharactersPerPoint: 100))
        let userID = UUID()
        let now = Date()

        let movement = LifeTrackerEvent(userID: userID, domain: .movement, occurredAt: now, value: 5000)
        let focus = LifeTrackerEvent(userID: userID, domain: .focus, occurredAt: now, value: 1800)
        let journal = LifeTrackerEvent(userID: userID, domain: .journal, occurredAt: now, value: 400)

        let p1 = engine.pointPolicy.points(for: movement)
        XCTAssertEqual(p1.movement, 20)
        XCTAssertEqual(p1.focus, 0)
        XCTAssertEqual(p1.journal, 0)

        let p2 = engine.pointPolicy.points(for: focus)
        XCTAssertEqual(p2.focus, 2)

        let p3 = engine.pointPolicy.points(for: journal)
        XCTAssertEqual(p3.journal, 4)
    }

    func test_upsertDailySummary_computesDailyScore() {
        let engine = LifeTrackerEngine(pointPolicy: .init(movementStepsPerPoint: 250, focusSecondsPerPoint: 900, journalCharactersPerPoint: 100))
        let userID = UUID()

        let calendar = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 5
        comps.day = 4
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        let date = calendar.date(from: comps)! 

        let events: [LifeTrackerEvent] = [
            .init(userID: userID, domain: .movement, occurredAt: date.addingTimeInterval(3600), value: 5000),
            .init(userID: userID, domain: .focus, occurredAt: date.addingTimeInterval(7200), value: 1800),
            .init(userID: userID, domain: .journal, occurredAt: date.addingTimeInterval(10800), value: 400)
        ]

        let record = engine.upsertDailySummary(existing: nil, userID: userID, date: date, events: events, calendar: calendar)

        // Expected: base 50 + movement(5000/250=20) + focus(1800/900=2) + journal(400/100=4) = 76.
        XCTAssertEqual(record.totalScore ?? -1, 76, accuracy: 0.0001)
        XCTAssertEqual(record.movementPoints, 20, accuracy: 0.0001)
        XCTAssertEqual(record.focusPoints, 2, accuracy: 0.0001)
        XCTAssertEqual(record.journalPoints, 4, accuracy: 0.0001)
        XCTAssertNotNil(record.breakdown["movementPoints"])
    }

    func test_generateWeeklyReview_includesMomentumTrendUpAndTopDomain() {
        let engine = LifeTrackerEngine(pointPolicy: .init())
        let calendar = Calendar(identifier: .gregorian)
        let userID = UUID()

        func makeDay(_ dayOffset: Int, score: Double) -> LifeTrackerDayRecord {
            let base = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
            let date = base.addingTimeInterval(TimeInterval(dayOffset) * 86400)
            let movement = score - 50 // invert-ish; use only totals for highlights.
            let record = LifeTrackerDayRecord(userID: userID, date: calendar.startOfDay(for: date), movementPoints: max(0, movement), focusPoints: 0, journalPoints: 0, sleepRegularityPoints: nil, highRiskUsagePenalty: 0, overrunPenalty: 0, lateNightPenalty: 0, repeatedRequestPenalty: 0, totalScore: score, breakdown: ["movementPoints": max(0, movement)])
            return record
        }

        // 7 days, increasing scores -> momentum should trend up.
        let days = (0..<7).map { makeDay($0, score: 50 + Double($0) * 5) }
        let weekStart = calendar.startOfDay(for: days.first!.date)
        let weekEnd = calendar.startOfDay(for: days.last!.date)

        let review = engine.generateWeeklyReview(weekStart: weekStart, weekEnd: weekEnd, days: days, calendar: calendar)
        XCTAssertFalse(review.highlights.isEmpty)
        XCTAssertTrue(review.highlights.contains(where: { $0.lowercased().contains("momentum") && $0.lowercased().contains("trending up") }))
        XCTAssertTrue(review.highlights.contains(where: { $0.lowercased().contains("top domain") && $0.lowercased().contains("movement") }))
    }
}
