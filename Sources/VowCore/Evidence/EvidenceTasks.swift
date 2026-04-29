import Foundation

// MARK: - Concrete task types

public final class StepsEvidenceTask: EvidenceTask, @unchecked Sendable {
    public let id: UUID
    public let createdAt: Date
    public var completedAt: Date?

    public let unlockRequestedAt: Date
    public let targetStepsDelta: Int

    public var type: EvidenceTaskType { .steps }

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        unlockRequestedAt: Date,
        targetStepsDelta: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.unlockRequestedAt = unlockRequestedAt
        self.targetStepsDelta = targetStepsDelta
    }

    public func isCompleted(at date: Date) -> Bool {
        EvidenceTaskCompletionLogic.isCompleted(completedAt, at: date)
    }
}

public final class FocusTimerEvidenceTask: EvidenceTask, @unchecked Sendable {
    public let id: UUID
    public let createdAt: Date
    public var completedAt: Date?

    public let unlockRequestedAt: Date
    public let targetSeconds: TimeInterval
    public let allowsPause: Bool

    public var type: EvidenceTaskType { .focusTimer }

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        unlockRequestedAt: Date,
        targetSeconds: TimeInterval,
        allowsPause: Bool
    ) {
        self.id = id
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.unlockRequestedAt = unlockRequestedAt
        self.targetSeconds = targetSeconds
        self.allowsPause = allowsPause
    }

    public func isCompleted(at date: Date) -> Bool {
        EvidenceTaskCompletionLogic.isCompleted(completedAt, at: date)
    }
}

public final class JournalEvidenceTask: EvidenceTask, @unchecked Sendable {
    public let id: UUID
    public let createdAt: Date
    public var completedAt: Date?

    public let unlockRequestedAt: Date
    public let minCharacters: Int
    public let minMeaningfulTokenCount: Int?
    public let maxSpamRepetitionRatio: Double

    public var type: EvidenceTaskType { .journal }

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        unlockRequestedAt: Date,
        minCharacters: Int,
        minMeaningfulTokenCount: Int? = nil,
        maxSpamRepetitionRatio: Double
    ) {
        self.id = id
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.unlockRequestedAt = unlockRequestedAt
        self.minCharacters = minCharacters
        self.minMeaningfulTokenCount = minMeaningfulTokenCount
        self.maxSpamRepetitionRatio = maxSpamRepetitionRatio
    }

    public func isCompleted(at date: Date) -> Bool {
        EvidenceTaskCompletionLogic.isCompleted(completedAt, at: date)
    }
}

// MARK: - Runner types

public struct StepsEvidenceTaskRunner<Provider: StepsEvidenceDataSource>: EvidenceTaskRunner {
    public typealias Task = StepsEvidenceTask

    public let provider: Provider

    public init(provider: Provider) {
        self.provider = provider
    }

    public func start(_ task: StepsEvidenceTask) async throws {
        // Host app handles HealthKit authorization + starts any needed observation.
    }

    public func checkCompletion(_ task: StepsEvidenceTask, at date: Date) async -> Bool {
        if task.isCompleted(at: date) { return true }
        do {
            let stepsDelta = try await provider.stepsDelta(from: task.unlockRequestedAt, until: date)
            if stepsDelta >= task.targetStepsDelta {
                task.completedAt = date
                return true
            }
            return false
        } catch {
            return false
        }
    }
}

public struct FocusTimerEvidenceTaskRunner<Provider: FocusEvidenceDataSource>: EvidenceTaskRunner {
    public typealias Task = FocusTimerEvidenceTask

    public let provider: Provider

    public init(provider: Provider) {
        self.provider = provider
    }

    public func start(_ task: FocusTimerEvidenceTask) async throws {
        // Host app starts foreground/background focus observation.
    }

    public func checkCompletion(_ task: FocusTimerEvidenceTask, at date: Date) async -> Bool {
        if task.isCompleted(at: date) { return true }
        do {
            let seconds = try await provider.focusSeconds(from: task.unlockRequestedAt, until: date)
            guard seconds >= task.targetSeconds else { return false }

            if !task.allowsPause {
                let interrupted = try await provider.hasFocusInterruption(from: task.unlockRequestedAt, until: date)
                guard !interrupted else { return false }
            }

            task.completedAt = date
            return true
        } catch {
            return false
        }
    }
}

public struct JournalEvidenceTaskRunner<Provider: JournalEvidenceDataSource>: EvidenceTaskRunner {
    public typealias Task = JournalEvidenceTask

    public let provider: Provider

    public init(provider: Provider) {
        self.provider = provider
    }

    public func start(_ task: JournalEvidenceTask) async throws {
        // Host app may compute journal completion / anti-spam analysis.
    }

    public func checkCompletion(_ task: JournalEvidenceTask, at date: Date) async -> Bool {
        if task.isCompleted(at: date) { return true }
        do {
            let obs = try await provider.journalObservation(from: task.unlockRequestedAt, until: date)

            guard obs.characterCount >= task.minCharacters else { return false }
            if let minTokens = task.minMeaningfulTokenCount {
                let actualTokens = obs.meaningfulTokenCount ?? 0
                guard actualTokens >= minTokens else { return false }
            }

            if let spamRatio = obs.spamRepetitionRatio {
                guard spamRatio <= task.maxSpamRepetitionRatio else { return false }
            }

            task.completedAt = date
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Builders

public enum EvidenceTaskBuilder {
    public static func makeStepsTask(unlockRequestedAt: Date, policy: EvidencePolicy) -> StepsEvidenceTask {
        StepsEvidenceTask(unlockRequestedAt: unlockRequestedAt, targetStepsDelta: policy.stepsTargetDelta)
    }

    public static func makeFocusTask(unlockRequestedAt: Date, policy: EvidencePolicy) -> FocusTimerEvidenceTask {
        FocusTimerEvidenceTask(
            unlockRequestedAt: unlockRequestedAt,
            targetSeconds: policy.focusTargetSeconds,
            allowsPause: policy.focusAllowsPause
        )
    }

    public static func makeJournalTask(unlockRequestedAt: Date, policy: EvidencePolicy) -> JournalEvidenceTask {
        JournalEvidenceTask(
            unlockRequestedAt: unlockRequestedAt,
            minCharacters: policy.journalMinCharacters,
            minMeaningfulTokenCount: policy.journalMinMeaningfulTokenCount,
            maxSpamRepetitionRatio: policy.journalMaxSpamRepetitionRatio
        )
    }
}

