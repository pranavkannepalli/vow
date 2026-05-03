import Foundation

public struct LifeTrackerDayRecord: Codable, Hashable, Identifiable {
    public var id: UUID
    public var userID: UUID

    /// Local calendar day.
    public var date: Date

    public var movementPoints: Double
    public var focusPoints: Double
    public var journalPoints: Double
    public var sleepRegularityPoints: Double?

    public var highRiskUsagePenalty: Double
    public var overrunPenalty: Double
    public var lateNightPenalty: Double
    public var repeatedRequestPenalty: Double

    public var totalScore: Double?
    public var breakdown: [String: Double]

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        userID: UUID,
        date: Date,
        movementPoints: Double = 0,
        focusPoints: Double = 0,
        journalPoints: Double = 0,
        sleepRegularityPoints: Double? = nil,
        highRiskUsagePenalty: Double = 0,
        overrunPenalty: Double = 0,
        lateNightPenalty: Double = 0,
        repeatedRequestPenalty: Double = 0,
        totalScore: Double? = nil,
        breakdown: [String: Double] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.date = date

        self.movementPoints = movementPoints
        self.focusPoints = focusPoints
        self.journalPoints = journalPoints
        self.sleepRegularityPoints = sleepRegularityPoints

        self.highRiskUsagePenalty = highRiskUsagePenalty
        self.overrunPenalty = overrunPenalty
        self.lateNightPenalty = lateNightPenalty
        self.repeatedRequestPenalty = repeatedRequestPenalty

        self.totalScore = totalScore
        self.breakdown = breakdown

        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
