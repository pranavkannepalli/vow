import XCTest
@testable import VowCore

final class NotificationComposerTests: XCTestCase {
    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps)!
    }

    func test_habit_reminders_enabled_generates_requests_for_uncompleted_instances() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = makeDate(year: 2026, month: 5, day: 4, hour: 22, minute: 0, calendar: calendar)

        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let habitDefID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let habitInstID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!

        let habitDefinitions = [AtomicHabitDefinitionRecord(
            id: habitDefID,
            userID: userID,
            name: "Journal",
            habitKind: .journalCompleted
        )]

        let habitInstances = [AtomicHabitInstanceRecord(
            id: habitInstID,
            userID: userID,
            habitDefinitionID: habitDefID,
            date: makeDate(year: 2026, month: 5, day: 4, hour: 0, minute: 0, calendar: calendar),
            status: .notStarted
        )]

        var prefs = NotificationPreferences(
            habitRemindersEnabled: true,
            dailyCheckInEnabled: false,
            focusSessionStartNudgeEnabled: false,
            habitReminderHour: 9,
            habitReminderMinute: 0
        )

        let composer = NotificationComposer()
        let evidencePolicy = EvidencePolicy(journalMinCharacters: 10)

        let requests = composer.compose(
            now: now,
            preferences: prefs,
            habitInstances: habitInstances,
            habitDefinitions: habitDefinitions,
            focusStatus: FocusSessionStatus(isInFocusSession: false, completed: false),
            evidencePolicy: evidencePolicy,
            calendar: calendar
        )

        XCTAssertEqual(requests.count, 1)
        let req = requests[0]
        XCTAssertEqual(req.kind, .habitReminders)
        XCTAssertEqual(req.identifier, "habit_reminder_\(habitInstID.uuidString)")
        XCTAssertEqual(req.scheduledAt, makeDate(year: 2026, month: 5, day: 5, hour: 9, minute: 0, calendar: calendar))
        XCTAssertEqual(req.content.title, "Vow habit nudge")
        XCTAssertEqual(req.content.body, "Write at least 10 characters in your journal entry since your unlock request.")
    }

    func test_daily_check_in_prompt_generated_when_enabled() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = makeDate(year: 2026, month: 5, day: 4, hour: 22, minute: 0, calendar: calendar)
        let startOfToday = calendar.startOfDay(for: now)
        let expectedIdentifier = "daily_check_in_\(Int(startOfToday.timeIntervalSince1970))"

        let composer = NotificationComposer()
        let prefs = NotificationPreferences(
            habitRemindersEnabled: false,
            dailyCheckInEnabled: true,
            focusSessionStartNudgeEnabled: false,
            dailyCheckInHour: 20,
            dailyCheckInMinute: 0
        )

        let requests = composer.compose(
            now: now,
            preferences: prefs,
            habitInstances: [],
            habitDefinitions: [],
            focusStatus: FocusSessionStatus(isInFocusSession: false, completed: true),
            evidencePolicy: EvidencePolicy(),
            calendar: calendar
        )

        XCTAssertEqual(requests.count, 1)
        let req = requests[0]
        XCTAssertEqual(req.kind, .dailyCheckInPrompt)
        XCTAssertEqual(req.identifier, expectedIdentifier)
        XCTAssertEqual(req.scheduledAt, makeDate(year: 2026, month: 5, day: 5, hour: 20, minute: 0, calendar: calendar))
        XCTAssertEqual(req.content.title, "Life check-in")
        XCTAssertEqual(req.content.body, "What did you do today that you’re proud of—what will you do next?")
    }

    func test_focus_session_start_nudge_generated_when_enabled_and_idle() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = makeDate(year: 2026, month: 5, day: 4, hour: 22, minute: 0, calendar: calendar)
        let startOfToday = calendar.startOfDay(for: now)
        let expectedIdentifier = "focus_start_nudge_\(Int(startOfToday.timeIntervalSince1970))"

        let composer = NotificationComposer()
        let prefs = NotificationPreferences(
            habitRemindersEnabled: false,
            dailyCheckInEnabled: false,
            focusSessionStartNudgeEnabled: true,
            focusSessionStartNudgeHour: 11,
            focusSessionStartNudgeMinute: 30
        )

        let requests = composer.compose(
            now: now,
            preferences: prefs,
            habitInstances: [],
            habitDefinitions: [],
            focusStatus: FocusSessionStatus(isInFocusSession: false, completed: false),
            calendar: calendar
        )

        XCTAssertEqual(requests.count, 1)
        let req = requests[0]
        XCTAssertEqual(req.kind, .focusSessionStartNudge)
        XCTAssertEqual(req.identifier, expectedIdentifier)
        XCTAssertEqual(req.scheduledAt, makeDate(year: 2026, month: 5, day: 5, hour: 11, minute: 30, calendar: calendar))
        XCTAssertEqual(req.content.title, "Start focus sprint")
    }
}
