import Foundation

/// Domain-based life logging inputs that can be aggregated into daily scores and weekly reviews.
public enum LifeTrackerDomain: String, Codable, Hashable, CaseIterable {
    case movement
    case focus
    case journal
    case sleepRegularity
}

/// A single life-logging event.
///
/// `value` is domain-specific:
/// - movement: steps
/// - focus: focus seconds
/// - journal: journal character count
/// - sleepRegularity: sleep regularity points (already points)
public struct LifeTrackerEvent: Codable, Hashable, Identifiable {
    public var id: UUID
    public var userID: UUID
    public var domain: LifeTrackerDomain
    public var occurredAt: Date
    public var value: Double

    public init(
        id: UUID = UUID(),
        userID: UUID,
        domain: LifeTrackerDomain,
        occurredAt: Date,
        value: Double
    ) {
        self.id = id
        self.userID = userID
        self.domain = domain
        self.occurredAt = occurredAt
        self.value = value
    }
}

/// Conversion from raw event values into the point buckets used by `DailyScore`.
public struct LifeTrackerPointPolicy: Codable, Hashable {
    /// movementPoints = steps / movementStepsPerPoint
    public var movementStepsPerPoint: Double

    /// focusPoints = seconds / focusSecondsPerPoint
    public var focusSecondsPerPoint: Double

    /// journalPoints = characters / journalCharactersPerPoint
    public var journalCharactersPerPoint: Double

    /// sleepRegularityPoints is already points; this multiplier allows tuning.
    public var sleepRegularityMultiplier: Double

    public init(
        movementStepsPerPoint: Double = 250,
        focusSecondsPerPoint: Double = 900,
        journalCharactersPerPoint: Double = 100,
        sleepRegularityMultiplier: Double = 1.0
    ) {
        self.movementStepsPerPoint = movementStepsPerPoint
        self.focusSecondsPerPoint = focusSecondsPerPoint
        self.journalCharactersPerPoint = journalCharactersPerPoint
        self.sleepRegularityMultiplier = sleepRegularityMultiplier
    }

    public func points(for event: LifeTrackerEvent) -> (movement: Double, focus: Double, journal: Double, sleepRegularity: Double) {
        switch event.domain {
        case .movement:
            return (
                movement: max(0, event.value / movementStepsPerPoint),
                focus: 0,
                journal: 0,
                sleepRegularity: 0
            )
        case .focus:
            return (
                movement: 0,
                focus: max(0, event.value / focusSecondsPerPoint),
                journal: 0,
                sleepRegularity: 0
            )
        case .journal:
            return (
                movement: 0,
                focus: 0,
                journal: max(0, event.value / journalCharactersPerPoint),
                sleepRegularity: 0
            )
        case .sleepRegularity:
            return (
                movement: 0,
                focus: 0,
                journal: 0,
                sleepRegularity: max(0, event.value) * sleepRegularityMultiplier
            )
        }
    }
}

public struct LifeTrackerDailySummary: Codable, Hashable {
    public var date: Date
    public var totalScore: Double
    public var movementPoints: Double
    public var focusPoints: Double
    public var journalPoints: Double
    public var sleepRegularityPoints: Double?

    public var highRiskUsagePenalty: Double
    public var overrunPenalty: Double
    public var lateNightPenalty: Double
    public var repeatedRequestPenalty: Double

    /// Simple breakdown map for UI/debug.
    public var breakdown: [String: Double]

    public init(
        date: Date,
        totalScore: Double,
        movementPoints: Double,
        focusPoints: Double,
        journalPoints: Double,
        sleepRegularityPoints: Double?,
        highRiskUsagePenalty: Double,
        overrunPenalty: Double,
        lateNightPenalty: Double,
        repeatedRequestPenalty: Double,
        breakdown: [String: Double]
    ) {
        self.date = date
        self.totalScore = totalScore
        self.movementPoints = movementPoints
        self.focusPoints = focusPoints
        self.journalPoints = journalPoints
        self.sleepRegularityPoints = sleepRegularityPoints
        self.highRiskUsagePenalty = highRiskUsagePenalty
        self.overrunPenalty = overrunPenalty
        self.lateNightPenalty = lateNightPenalty
        self.repeatedRequestPenalty = repeatedRequestPenalty
        self.breakdown = breakdown
    }
}

public struct LifeTrackerWeeklyReview: Codable, Hashable {
    public var weekStart: Date
    public var weekEnd: Date
    public var days: [LifeTrackerDailySummary]

    public var averageScore: Double
    public var totalMovementPoints: Double
    public var totalFocusPoints: Double
    public var totalJournalPoints: Double

    public var highlights: [String]

    public init(
        weekStart: Date,
        weekEnd: Date,
        days: [LifeTrackerDailySummary],
        averageScore: Double,
        totalMovementPoints: Double,
        totalFocusPoints: Double,
        totalJournalPoints: Double,
        highlights: [String]
    ) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.days = days
        self.averageScore = averageScore
        self.totalMovementPoints = totalMovementPoints
        self.totalFocusPoints = totalFocusPoints
        self.totalJournalPoints = totalJournalPoints
        self.highlights = highlights
    }
}

public struct LifeTrackerEngine {
    public var pointPolicy: LifeTrackerPointPolicy

    public init(pointPolicy: LifeTrackerPointPolicy = .init()) {
        self.pointPolicy = pointPolicy
    }

    public func upsertDailySummary(
        existing: LifeTrackerDayRecord? = nil,
        userID: UUID,
        date: Date,
        events: [LifeTrackerEvent],
        calendar: Calendar = .current
    ) -> LifeTrackerDayRecord {
        let start = calendar.startOfDay(for: date)
        let userEvents = events.filter { $0.userID == userID }.filter { calendar.isDate($0.occurredAt, inSameDayAs: start) }

        let penalties = (
            existing?.highRiskUsagePenalty ?? 0,
            existing?.overrunPenalty ?? 0,
            existing?.lateNightPenalty ?? 0,
            existing?.repeatedRequestPenalty ?? 0
        )

        var movement = 0.0
        var focus = 0.0
        var journal = 0.0
        var sleep: Double? = nil

        for e in userEvents {
            let pts = pointPolicy.points(for: e)
            movement += pts.movement
            focus += pts.focus
            journal += pts.journal
            if e.domain == .sleepRegularity {
                // If multiple sleep events exist in a day, we sum them.
                sleep = (sleep ?? 0) + pts.sleepRegularity
            }
        }

        let inputs = DailyScoreInputs(
            movementPoints: movement,
            focusPoints: focus,
            journalPoints: journal,
            sleepRegularityPoints: sleep,
            highRiskUsagePenalty: penalties.0,
            overrunPenalty: penalties.1,
            lateNightPenalty: penalties.2,
            repeatedRequestPenalty: penalties.3
        )

        let total = DailyScore.compute(from: inputs)

        var breakdown: [String: Double] = [
            "movementPoints": movement,
            "focusPoints": focus,
            "journalPoints": journal
        ]
        if let s = sleep { breakdown["sleepRegularityPoints"] = s }
        breakdown["highRiskUsagePenalty"] = penalties.0
        breakdown["overrunPenalty"] = penalties.1
        breakdown["lateNightPenalty"] = penalties.2
        breakdown["repeatedRequestPenalty"] = penalties.3

        let now = Date()
        if var existing {
            existing.date = start
            existing.userID = userID
            existing.movementPoints = movement
            existing.focusPoints = focus
            existing.journalPoints = journal
            existing.sleepRegularityPoints = sleep
            existing.totalScore = total
            existing.breakdown = breakdown
            existing.updatedAt = now
            return existing
        }

        return LifeTrackerDayRecord(
            userID: userID,
            date: start,
            movementPoints: movement,
            focusPoints: focus,
            journalPoints: journal,
            sleepRegularityPoints: sleep,
            highRiskUsagePenalty: penalties.0,
            overrunPenalty: penalties.1,
            lateNightPenalty: penalties.2,
            repeatedRequestPenalty: penalties.3,
            totalScore: total,
            breakdown: breakdown,
            createdAt: now,
            updatedAt: now
        )
    }

    public func dailySummary(from record: LifeTrackerDayRecord) -> LifeTrackerDailySummary {
        let total = record.totalScore ?? 0
        return .init(
            date: record.date,
            totalScore: total,
            movementPoints: record.movementPoints,
            focusPoints: record.focusPoints,
            journalPoints: record.journalPoints,
            sleepRegularityPoints: record.sleepRegularityPoints,
            highRiskUsagePenalty: record.highRiskUsagePenalty,
            overrunPenalty: record.overrunPenalty,
            lateNightPenalty: record.lateNightPenalty,
            repeatedRequestPenalty: record.repeatedRequestPenalty,
            breakdown: record.breakdown
        )
    }

    public func generateWeeklyReview(
        weekStart: Date,
        weekEnd: Date,
        days: [LifeTrackerDayRecord],
        calendar: Calendar = .current
    ) -> LifeTrackerWeeklyReview {
        let start = calendar.startOfDay(for: weekStart)
        let end = calendar.startOfDay(for: weekEnd)

        let inRange = days
            .map { ($0, calendar.startOfDay(for: $0.date)) }
            .filter { _, d in d >= start && d <= end }
            .sorted { a, b in a.1 < b.1 }
            .map { $0.0 }

        let summaries = inRange.map(dailySummary(from:))

        let scores = summaries.map { $0.totalScore }
        let averageScore = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)

        let totalMovementPoints = summaries.reduce(0) { $0 + $1.movementPoints }
        let totalFocusPoints = summaries.reduce(0) { $0 + $1.focusPoints }
        let totalJournalPoints = summaries.reduce(0) { $0 + $1.journalPoints }

        var highlights: [String] = []

        if let best = summaries.max(by: { $0.totalScore < $1.totalScore }) {
            highlights.append("Best day: \(formatDate(best.date)) (score \(Int(best.totalScore.rounded())))")
        }
        if let worst = summaries.min(by: { $0.totalScore < $1.totalScore }) {
            highlights.append("Lowest day: \(formatDate(worst.date)) (score \(Int(worst.totalScore.rounded())))")
        }

        // Simple momentum: compare last 2 days avg vs previous days avg.
        if summaries.count >= 4 {
            let last2 = summaries.suffix(2)
            let prior = summaries.dropLast(2)

            let last2Avg = last2.map { $0.totalScore }.reduce(0, +) / Double(last2.count)
            let priorAvg = prior.map { $0.totalScore }.reduce(0, +) / Double(prior.count)

            let delta = last2Avg - priorAvg
            let trendWord: String
            if abs(delta) < 0.001 {
                trendWord = "steady"
            } else if delta > 0 {
                trendWord = "trending up"
            } else {
                trendWord = "trending down"
            }
            highlights.append("Momentum: last 2 days are \(trendWord) (Δ\(Int(delta.rounded())) pts)")
        }

        // Dominant domain by total points.
        let domainTotals: [(String, Double)] = [
            ("movement", totalMovementPoints),
            ("focus", totalFocusPoints),
            ("journal", totalJournalPoints)
        ]
        if let top = domainTotals.max(by: { $0.1 < $1.1 }) {
            highlights.append("Top domain: \(top.0) (\(Int(top.1.rounded())) pts)")
        }

        return .init(
            weekStart: start,
            weekEnd: end,
            days: summaries,
            averageScore: averageScore,
            totalMovementPoints: totalMovementPoints,
            totalFocusPoints: totalFocusPoints,
            totalJournalPoints: totalJournalPoints,
            highlights: highlights
        )
    }
}

private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = .current
    return formatter.string(from: date)
}
