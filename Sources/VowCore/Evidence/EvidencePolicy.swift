import Foundation

/// Evidence thresholds used to gate high-risk unlocks.
///
/// Core intentionally stays platform-agnostic: iOS/HealthKit/journal adapters are provided by the host app.
public struct EvidencePolicy: Codable, Hashable {
    /// Steps delta observed since the unlock request timestamp.
    public var stepsTargetDelta: Int

    /// Focus duration observed since the unlock request timestamp.
    public var focusTargetSeconds: TimeInterval

    /// Minimum character count for the journal task.
    public var journalMinCharacters: Int

    /// Optional minimum meaningful token count for the journal task.
    public var journalMinMeaningfulTokenCount: Int?

    /// Reject journal submissions with excessive repetition (0.0..1.0).
    public var journalMaxSpamRepetitionRatio: Double

    /// If false, any focus interruption invalidates completion.
    public var focusAllowsPause: Bool

    public init(
        stepsTargetDelta: Int = 1200,
        focusTargetSeconds: TimeInterval = 20 * 60,
        journalMinCharacters: Int = 200,
        journalMinMeaningfulTokenCount: Int? = nil,
        journalMaxSpamRepetitionRatio: Double = 0.35,
        focusAllowsPause: Bool = false
    ) {
        self.stepsTargetDelta = stepsTargetDelta
        self.focusTargetSeconds = focusTargetSeconds
        self.journalMinCharacters = journalMinCharacters
        self.journalMinMeaningfulTokenCount = journalMinMeaningfulTokenCount
        self.journalMaxSpamRepetitionRatio = journalMaxSpamRepetitionRatio
        self.focusAllowsPause = focusAllowsPause
    }
}

