import Foundation

/// Serializable inputs for an evidence task as declared by an external system
/// (e.g. ChaosHQ mirror intake).
public enum EvidenceTaskInput: Codable, Hashable {
    case steps(StepsEvidenceTaskInput)
    case focusTimer(FocusTimerEvidenceTaskInput)
    case journal(JournalEvidenceTaskInput)
}

public struct StepsEvidenceTaskInput: Codable, Hashable {
    public let taskID: UUID
    public let unlockRequestedAt: Date
    public let targetStepsDelta: Int

    public init(taskID: UUID, unlockRequestedAt: Date, targetStepsDelta: Int) {
        self.taskID = taskID
        self.unlockRequestedAt = unlockRequestedAt
        self.targetStepsDelta = targetStepsDelta
    }
}

public struct FocusTimerEvidenceTaskInput: Codable, Hashable {
    public let taskID: UUID
    public let unlockRequestedAt: Date
    public let targetSeconds: TimeInterval
    public let allowsPause: Bool

    public init(
        taskID: UUID,
        unlockRequestedAt: Date,
        targetSeconds: TimeInterval,
        allowsPause: Bool
    ) {
        self.taskID = taskID
        self.unlockRequestedAt = unlockRequestedAt
        self.targetSeconds = targetSeconds
        self.allowsPause = allowsPause
    }
}

public struct JournalEvidenceTaskInput: Codable, Hashable {
    public let taskID: UUID
    public let unlockRequestedAt: Date
    public let minCharacters: Int
    public let minMeaningfulTokenCount: Int?
    public let maxSpamRepetitionRatio: Double

    public init(
        taskID: UUID,
        unlockRequestedAt: Date,
        minCharacters: Int,
        minMeaningfulTokenCount: Int? = nil,
        maxSpamRepetitionRatio: Double
    ) {
        self.taskID = taskID
        self.unlockRequestedAt = unlockRequestedAt
        self.minCharacters = minCharacters
        self.minMeaningfulTokenCount = minMeaningfulTokenCount
        self.maxSpamRepetitionRatio = maxSpamRepetitionRatio
    }
}

public extension EvidenceTaskInput {
    /// Best-effort conversion into concrete VowCore evidence task instances.
    ///
    /// Host apps can still choose to run different completion logic; this
    /// conversion is provided primarily for wiring and tests.
    func toConcreteTask() -> any EvidenceTask {
        switch self {
        case .steps(let input):
            return StepsEvidenceTask(
                id: input.taskID,
                createdAt: input.unlockRequestedAt,
                completedAt: nil,
                unlockRequestedAt: input.unlockRequestedAt,
                targetStepsDelta: input.targetStepsDelta
            )
        case .focusTimer(let input):
            return FocusTimerEvidenceTask(
                id: input.taskID,
                createdAt: input.unlockRequestedAt,
                completedAt: nil,
                unlockRequestedAt: input.unlockRequestedAt,
                targetSeconds: input.targetSeconds,
                allowsPause: input.allowsPause
            )
        case .journal(let input):
            return JournalEvidenceTask(
                id: input.taskID,
                createdAt: input.unlockRequestedAt,
                completedAt: nil,
                unlockRequestedAt: input.unlockRequestedAt,
                minCharacters: input.minCharacters,
                minMeaningfulTokenCount: input.minMeaningfulTokenCount,
                maxSpamRepetitionRatio: input.maxSpamRepetitionRatio
            )
        }
    }
}
