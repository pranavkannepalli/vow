import Foundation


// MARK: - Payloads

/// ChaosHQ payload representing a “mirror intake” of evidence requirements.
///
/// The exact ChaosHQ JSON schema can evolve; this type is intentionally
/// permissive (optional per-field parameters, strong required IDs).
public struct ChaosHqMirrorIntakePayload: Codable, Hashable {
    /// ChaosHQ task identifier for traceability.
    public let chaosTaskID: UUID

    /// ChaosHQ execution identifier for traceability.
    public let chaosExecutionID: UUID

    /// Evidence requirements to gate an unlock.
    public let evidenceTasks: [ChaosHqEvidenceTaskPayload]

    public init(
        chaosTaskID: UUID,
        chaosExecutionID: UUID,
        evidenceTasks: [ChaosHqEvidenceTaskPayload] = []
    ) {
        self.chaosTaskID = chaosTaskID
        self.chaosExecutionID = chaosExecutionID
        self.evidenceTasks = evidenceTasks
    }
}

/// A single ChaosHQ-declared evidence requirement.
public struct ChaosHqEvidenceTaskPayload: Codable, Hashable {
    public let type: EvidenceTaskType

    // Optional per-field parameters; if nil, defaults from `EvidencePolicy` are used.
    public let stepsTargetDelta: Int?
    public let focusTargetSeconds: TimeInterval?
    public let allowsPause: Bool?

    public let journalMinCharacters: Int?
    public let journalMinMeaningfulTokenCount: Int?
    public let journalMaxSpamRepetitionRatio: Double?

    public init(
        type: EvidenceTaskType,
        stepsTargetDelta: Int? = nil,
        focusTargetSeconds: TimeInterval? = nil,
        allowsPause: Bool? = nil,
        journalMinCharacters: Int? = nil,
        journalMinMeaningfulTokenCount: Int? = nil,
        journalMaxSpamRepetitionRatio: Double? = nil
    ) {
        self.type = type
        self.stepsTargetDelta = stepsTargetDelta
        self.focusTargetSeconds = focusTargetSeconds
        self.allowsPause = allowsPause
        self.journalMinCharacters = journalMinCharacters
        self.journalMinMeaningfulTokenCount = journalMinMeaningfulTokenCount
        self.journalMaxSpamRepetitionRatio = journalMaxSpamRepetitionRatio
    }
}

// MARK: - Plan

public struct ChaosHqEvidencePlan: Codable, Hashable {
    public let chaosTaskID: UUID
    public let chaosExecutionID: UUID
    public let unlockRequestedAt: Date

    public let evidenceTaskInputs: [EvidenceTaskInput]

    public init(
        chaosTaskID: UUID,
        chaosExecutionID: UUID,
        unlockRequestedAt: Date,
        evidenceTaskInputs: [EvidenceTaskInput]
    ) {
        self.chaosTaskID = chaosTaskID
        self.chaosExecutionID = chaosExecutionID
        self.unlockRequestedAt = unlockRequestedAt
        self.evidenceTaskInputs = evidenceTaskInputs
    }
}

public enum ChaosHqAdapterError: Error {
    case noEvidenceTasks
    case unsupportedEvidenceType
}

// MARK: - Adapter

public protocol ChaosHqAdapter {
    /// Maps ChaosHQ “mirror intake” into a VowCore evidence plan.
    func mapMirrorIntake(
        _ payload: ChaosHqMirrorIntakePayload,
        policy: EvidencePolicy,
        unlockRequestedAt: Date
    ) throws -> ChaosHqEvidencePlan
}

public struct DefaultChaosHqAdapter: ChaosHqAdapter {
    public init() {}

    public func mapMirrorIntake(
        _ payload: ChaosHqMirrorIntakePayload,
        policy: EvidencePolicy,
        unlockRequestedAt: Date
    ) throws -> ChaosHqEvidencePlan {
        guard !payload.evidenceTasks.isEmpty else {
            throw ChaosHqAdapterError.noEvidenceTasks
        }

        let inputs: [EvidenceTaskInput] = payload.evidenceTasks.compactMap { taskPayload in
            switch taskPayload.type {
            case .steps:
                let delta = taskPayload.stepsTargetDelta ?? policy.stepsTargetDelta
                return .steps(
                    .init(
                        taskID: UUID(),
                        unlockRequestedAt: unlockRequestedAt,
                        targetStepsDelta: delta
                    )
                )

            case .focusTimer:
                let seconds = taskPayload.focusTargetSeconds ?? policy.focusTargetSeconds
                let allowsPause = taskPayload.allowsPause ?? policy.focusAllowsPause
                return .focusTimer(
                    .init(
                        taskID: UUID(),
                        unlockRequestedAt: unlockRequestedAt,
                        targetSeconds: seconds,
                        allowsPause: allowsPause
                    )
                )

            case .journal:
                let minChars = taskPayload.journalMinCharacters ?? policy.journalMinCharacters
                let minMeaningfulTokens = taskPayload.journalMinMeaningfulTokenCount ?? policy.journalMinMeaningfulTokenCount
                let maxSpamRatio = taskPayload.journalMaxSpamRepetitionRatio ?? policy.journalMaxSpamRepetitionRatio

                return .journal(
                    .init(
                        taskID: UUID(),
                        unlockRequestedAt: unlockRequestedAt,
                        minCharacters: minChars,
                        minMeaningfulTokenCount: minMeaningfulTokens,
                        maxSpamRepetitionRatio: maxSpamRatio
                    )
                )
            }
        }

        guard !inputs.isEmpty else {
            throw ChaosHqAdapterError.noEvidenceTasks
        }

        return ChaosHqEvidencePlan(
            chaosTaskID: payload.chaosTaskID,
            chaosExecutionID: payload.chaosExecutionID,
            unlockRequestedAt: unlockRequestedAt,
            evidenceTaskInputs: inputs
        )
    }
}
