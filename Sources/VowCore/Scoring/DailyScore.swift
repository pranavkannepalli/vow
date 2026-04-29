import Foundation

public struct DailyScoreInputs: Codable, Hashable {
    public var movementPoints: Double
    public var focusPoints: Double
    public var journalPoints: Double
    public var sleepRegularityPoints: Double?

    public var highRiskUsagePenalty: Double
    public var overrunPenalty: Double
    public var lateNightPenalty: Double
    public var repeatedRequestPenalty: Double

    public init(
        movementPoints: Double = 0,
        focusPoints: Double = 0,
        journalPoints: Double = 0,
        sleepRegularityPoints: Double? = nil,
        highRiskUsagePenalty: Double = 0,
        overrunPenalty: Double = 0,
        lateNightPenalty: Double = 0,
        repeatedRequestPenalty: Double = 0
    ) {
        self.movementPoints = movementPoints
        self.focusPoints = focusPoints
        self.journalPoints = journalPoints
        self.sleepRegularityPoints = sleepRegularityPoints
        self.highRiskUsagePenalty = highRiskUsagePenalty
        self.overrunPenalty = overrunPenalty
        self.lateNightPenalty = lateNightPenalty
        self.repeatedRequestPenalty = repeatedRequestPenalty
    }
}

public struct DailyScore: Codable, Hashable {
    /// v1 formula: PRD `score = 50 + ... - penalties`, clamped 0...100
    public static func compute(from inputs: DailyScoreInputs) -> Double {
        var score = 50.0
        score += inputs.movementPoints
        score += inputs.focusPoints
        score += inputs.journalPoints
        if let s = inputs.sleepRegularityPoints { score += s }

        score -= inputs.highRiskUsagePenalty
        score -= inputs.overrunPenalty
        score -= inputs.lateNightPenalty
        score -= inputs.repeatedRequestPenalty

        return min(100.0, max(0.0, score))
    }
}
