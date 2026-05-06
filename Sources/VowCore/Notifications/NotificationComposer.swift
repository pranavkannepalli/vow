import Foundation

public struct FocusSessionStatus: Codable, Hashable, Equatable {
    public var isInFocusSession: Bool
    public var completed: Bool

    public init(isInFocusSession: Bool, completed: Bool) {
        self.isInFocusSession = isInFocusSession
        self.completed = completed
    }
}

/// Creates notification requests (content + schedule) from the app’s
/// current state.
///
/// The host app is responsible for persisting preferences and wiring
/// the scheduler to OS notifications.
public struct NotificationComposer {
    public init() {}

    public func compose(
        now: Date,
        preferences: NotificationPreferences,
        habitInstances: [AtomicHabitInstanceRecord],
        habitDefinitions: [AtomicHabitDefinitionRecord],
        focusStatus: FocusSessionStatus,
        evidencePolicy: EvidencePolicy = EvidencePolicy(),
        calendar: Calendar = .current
    ) -> [NotificationRequest] {
        let defByID = Dictionary(uniqueKeysWithValues: habitDefinitions.map { ($0.id, $0) })
        let startOfToday = calendar.startOfDay(for: now)

        var requests: [NotificationRequest] = []

        // MARK: Habit reminders
        if preferences.habitRemindersEnabled {
            let habitReminderAt = nextOccurrence(
                hour: preferences.habitReminderHour,
                minute: preferences.habitReminderMinute,
                from: now,
                calendar: calendar
            )

            let todayInstances = habitInstances.filter { inst in
                calendar.isDate(inst.date, inSameDayAs: startOfToday)
            }

            for inst in todayInstances where inst.status != .completed {
                guard let def = defByID[inst.habitDefinitionID] else { continue }
                let engine = AtomicHabitEngine()
                let micro = engine.microCommitment(
                    habitKind: def.habitKind,
                    name: def.name,
                    evidencePolicy: evidencePolicy
                )

                requests.append(
                    NotificationRequest(
                        identifier: "habit_reminder_\(inst.id.uuidString)",
                        kind: .habitReminders,
                        scheduledAt: habitReminderAt,
                        content: .init(
                            title: "Vow habit nudge",
                            body: micro.description
                        )
                    )
                )
            }
        }

        // MARK: Daily check-in prompt
        if preferences.dailyCheckInEnabled {
            let dailyCheckInAt = nextOccurrence(
                hour: preferences.dailyCheckInHour,
                minute: preferences.dailyCheckInMinute,
                from: now,
                calendar: calendar
            )

            requests.append(
                NotificationRequest(
                    identifier: "daily_check_in_\(Int(startOfToday.timeIntervalSince1970))",
                    kind: .dailyCheckInPrompt,
                    scheduledAt: dailyCheckInAt,
                    content: .init(
                        title: "Life check-in",
                        body: "What did you do today that you’re proud of—what will you do next?"
                    )
                )
            )
        }

        // MARK: Focus session start nudges
        if preferences.focusSessionStartNudgeEnabled {
            if focusStatus.isInFocusSession == false && focusStatus.completed == false {
                let focusNudgeAt = nextOccurrence(
                    hour: preferences.focusSessionStartNudgeHour,
                    minute: preferences.focusSessionStartNudgeMinute,
                    from: now,
                    calendar: calendar
                )

                requests.append(
                    NotificationRequest(
                        identifier: "focus_start_nudge_\(Int(startOfToday.timeIntervalSince1970))",
                        kind: .focusSessionStartNudge,
                        scheduledAt: focusNudgeAt,
                        content: .init(
                            title: "Start focus sprint",
                            body: "Tiny start beats perfect start—start your focus sprint now."
                        )
                    )
                )
            }
        }

        return requests.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private func nextOccurrence(
        hour: Int,
        minute: Int,
        from now: Date,
        calendar: Calendar
    ) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0

        let candidate = calendar.date(from: comps) ?? now
        if candidate <= now {
            return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }
}
