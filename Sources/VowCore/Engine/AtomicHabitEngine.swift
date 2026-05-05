import Foundation

/// Core engine for turning “atomic habit” templates into daily instances,
/// evaluating completion with grace periods, computing streaks, and choosing
/// the next due/occurrence day.
public struct AtomicHabitEngine: Codable, Hashable {
    public var completionPolicy: AtomicHabitCompletionPolicy

    public init(completionPolicy: AtomicHabitCompletionPolicy = .init()) {
        self.completionPolicy = completionPolicy
    }

    // MARK: - Templates → instances

    /// Creates (or returns) a daily habit instance for `definition` on `instanceDate`.
    ///
    /// - If an instance already exists for the same `habitDefinitionID` and day,
    ///   it is returned unchanged.
    /// - Otherwise a new `.notStarted` instance is created.
    public func upsertDailyInstance(
        definition: AtomicHabitDefinitionRecord,
        instanceDate: Date,
        into instances: [AtomicHabitInstanceRecord],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [AtomicHabitInstanceRecord] {
        let day = calendar.startOfDay(for: instanceDate)

        if let existing = instances.first(where: { $0.habitDefinitionID == definition.id && calendar.isDate($0.date, inSameDayAs: day) }) {
            return instances
        }

        // occuranceCount represents how many times the user has completed this habit historically
        // (not counting this new instance).
        let priorCompletedCount = instances
            .filter { $0.habitDefinitionID == definition.id }
            .filter { $0.status == .completed }
            .count

        let created = AtomicHabitInstanceRecord(
            userID: definition.userID,
            habitDefinitionID: definition.id,
            date: day,
            status: .notStarted,
            completedAt: nil,
            occurrenceCount: priorCompletedCount,
            evidence: [:],
            createdAt: now,
            updatedAt: now
        )

        return instances + [created]
    }

    // MARK: - Micro-commitments

    public struct MicroCommitment: Codable, Hashable {
        public var title: String
        public var description: String
        public var evidenceTaskType: EvidenceTaskType?

        public init(title: String, description: String, evidenceTaskType: EvidenceTaskType? = nil) {
            self.title = title
            self.description = description
            self.evidenceTaskType = evidenceTaskType
        }
    }

    /// Converts a habit template (kind + name) into a user-facing micro-commitment.
    ///
    /// Evidence thresholds come from `evidencePolicy` when relevant.
    public func microCommitment(
        habitKind: AtomicHabitKind,
        name: String,
        evidencePolicy: EvidencePolicy? = nil
    ) -> MicroCommitment {
        switch habitKind {
        case .stepsCompleted:
            let delta = evidencePolicy?.stepsTargetDelta
            let desc = delta.map { "Walk at least \($0) steps since your unlock request." }
                ?? "Walk enough steps since your unlock request."
            return .init(title: "Micro-walk", description: desc, evidenceTaskType: .steps)

        case .focusSessionsCompleted:
            let seconds = evidencePolicy?.focusTargetSeconds
            let minutes = seconds.map { Int($0.rounded() / 60) }
            let desc = minutes.map { "Complete a focus session (about \($0) minutes) since your unlock request." }
                ?? "Complete a focus session since your unlock request."
            return .init(title: "Focus sprint", description: desc, evidenceTaskType: .focusTimer)

        case .journalCompleted:
            let minChars = evidencePolicy?.journalMinCharacters
            let desc = minChars.map { "Write at least \($0) characters in your journal entry since your unlock request." }
                ?? "Write a meaningful journal entry since your unlock request."
            return .init(title: "Journal check-in", description: desc, evidenceTaskType: .journal)

        case .generic:
            return .init(title: "Tiny next action", description: "Complete: \(name).", evidenceTaskType: nil)
        }
    }

    // MARK: - Completion with grace periods

    public enum CompletionQuality: String, Codable, Hashable {
        /// Completed before the next local day starts.
        case onTime
        /// Completed after the day flips, but still within the configured grace window.
        case withinGrace
        /// Completed too late to count for the target day.
        case missed
    }

    /// Determines whether a completion attempt counts for the instance's target day.
    public func completionQuality(
        instanceDate: Date,
        completedAt: Date,
        calendar: Calendar = .current
    ) -> CompletionQuality {
        let targetDay = calendar.startOfDay(for: instanceDate)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: targetDay)!
        let graceUntil = nextDay.addingTimeInterval(completionPolicy.dailyGracePeriodSeconds)

        if completedAt < nextDay {
            return .onTime
        }
        if completedAt < graceUntil {
            return .withinGrace
        }
        return .missed
    }

    /// Applies a completion attempt to an instance.
    ///
    /// - If the completion is within grace, the instance becomes `.completed`.
    /// - Otherwise it is marked as `.inProgress` (so evidence attempts are auditable,
    ///   but streaks/day-counting won't treat it as completed).
    public func attemptCompletion(
        instance: AtomicHabitInstanceRecord,
        completedAt: Date,
        evidence: [String: String] = [:],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> (updated: AtomicHabitInstanceRecord, accepted: Bool) {
        let quality = completionQuality(instanceDate: instance.date, completedAt: completedAt, calendar: calendar)
        switch quality {
        case .onTime, .withinGrace:
            var updated = instance
            updated.status = .completed
            updated.completedAt = completedAt
            updated.evidence = evidence.merging(updated.evidence) { _, new in new }
            updated.occurrenceCount = instance.occurrenceCount + 1
            updated.updatedAt = now
            return (updated, true)

        case .missed:
            var updated = instance
            updated.status = .inProgress
            updated.evidence = evidence.merging(updated.evidence) { _, new in new }
            updated.updatedAt = now
            return (updated, false)
        }
    }

    // MARK: - Streak computation

    public struct Streak: Codable, Hashable {
        public var current: Int
        public var best: Int
        public var endingOn: Date

        public init(current: Int, best: Int, endingOn: Date) {
            self.current = current
            self.best = best
            self.endingOn = endingOn
        }
    }

    public func computeStreak(
        habitDefinitionID: UUID,
        instances: [AtomicHabitInstanceRecord],
        asOf: Date,
        calendar: Calendar = .current
    ) -> Streak {
        let asOfDay = calendar.startOfDay(for: asOf)

        // Completed day keys (counting grace).
        let completedDays: Set<Date> = Set(
            instances
                .filter { $0.habitDefinitionID == habitDefinitionID }
                .filter { $0.status == .completed }
                .compactMap { inst in
                    guard let completedAt = inst.completedAt else { return nil }
                    let quality = completionQuality(instanceDate: inst.date, completedAt: completedAt, calendar: calendar)
                    guard quality != .missed else { return nil }
                    return calendar.startOfDay(for: inst.date)
                }
        )

        // Current streak: walk backwards from as-of day.
        var current = 0
        var cursor = asOfDay
        for _ in 0..<366 {
            if completedDays.contains(cursor) {
                current += 1
                cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
            } else {
                break
            }
        }

        // Best streak: scan consecutive days within completion span.
        let sorted = completedDays.sorted()
        var best = 0
        var run = 0
        var prev: Date? = nil

        for day in sorted {
            if let prev {
                let delta = calendar.dateComponents([.day], from: prev, to: day).day ?? 0
                if delta == 1 {
                    run += 1
                } else {
                    run = 1
                }
            } else {
                run = 1
            }
            best = max(best, run)
            prev = day
        }

        return Streak(current: current, best: best, endingOn: asOfDay)
    }

    // MARK: - Adaptive next occurrence logic

    /// Chooses the next due/occurrence day for a habit, using completion + grace.
    ///
    /// Current behavior:
    /// - If the habit is completed for the local `today` day, next is `tomorrow`.
    /// - Else if we're past the grace window for today, next is `tomorrow`.
    /// - Otherwise next is `today`.
    public func nextOccurrenceDate(
        habitDefinitionID: UUID,
        instances: [AtomicHabitInstanceRecord],
        now: Date,
        calendar: Calendar = .current
    ) -> Date {
        let today = calendar.startOfDay(for: now)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: today)!
        let graceUntil = nextDay.addingTimeInterval(completionPolicy.dailyGracePeriodSeconds)

        if let todaysInstance = instances
            .filter({ $0.habitDefinitionID == habitDefinitionID })
            .first(where: { inst in
                calendar.isDate(inst.date, inSameDayAs: today)
            }),
           todaysInstance.status == .completed,
           let completedAt = todaysInstance.completedAt {
            let quality = completionQuality(instanceDate: todaysInstance.date, completedAt: completedAt, calendar: calendar)
            if quality != .missed {
                return nextDay
            }
        }

        // Not completed for today (or completed too late).
        // If grace window is over, move to tomorrow.
        return now < graceUntil ? today : nextDay
    }
}

public struct AtomicHabitCompletionPolicy: Codable, Hashable {
    /// How long after the local day flips (i.e. after midnight) a completion can be
    /// accepted for the previous day.
    public var dailyGracePeriodSeconds: TimeInterval

    public init(dailyGracePeriodSeconds: TimeInterval = 2 * 60 * 60) {
        self.dailyGracePeriodSeconds = dailyGracePeriodSeconds
    }
}
