import Foundation

public enum UnlockDecision: String, Codable {
    case approved_temp_unlock
    case deferred
    case denied
}

public enum UnlockRequestEvent: Codable {
    case requestCreated
    case frictionTimerStarted
    case evidenceRequired
    case evidenceCompleted
    case aiReviewed

    case decisionApproved
    case decisionDeferred
    case decisionDenied

    case sessionObserved
    case sessionClosed
    case reviewLogged
}

/// The v1 state machine described in `vow_prd.md`.
public enum RequestState: String, Codable {
    case requestCreated
    case frictionWaiting
    case evidencePending
    case evidenceCompleted
    case aiReviewed
    case decisionApprovedTempUnlock
    case decisionDeferred
    case decisionDenied
    case sessionClosed
    case reviewLogged

    public var isTerminal: Bool {
        switch self {
        case .decisionDenied, .reviewLogged:
            return true
        default:
            return false
        }
    }
}

public struct RequestContextSnapshot: Codable, Hashable {
    public var relapseScoreContribution: Double
    public var dailyScoreAtRequest: Double
    public var priorUnlockCountToday: Int
    public var lateNightBucket: Bool

    public init(
        relapseScoreContribution: Double = 0,
        dailyScoreAtRequest: Double = 50,
        priorUnlockCountToday: Int = 0,
        lateNightBucket: Bool = false
    ) {
        self.relapseScoreContribution = relapseScoreContribution
        self.dailyScoreAtRequest = dailyScoreAtRequest
        self.priorUnlockCountToday = priorUnlockCountToday
        self.lateNightBucket = lateNightBucket
    }
}

/// Pure state-machine transitions (no timers, no UI).
public struct UnlockRequestStateMachine: Codable {
    public private(set) var state: RequestState
    public private(set) var evidenceRequired: Bool

    public init(evidenceRequired: Bool, startingState: RequestState = .requestCreated) {
        self.evidenceRequired = evidenceRequired
        self.state = startingState
    }

    public mutating func apply(_ event: UnlockRequestEvent) {
        switch (state, event, evidenceRequired) {
        case (.requestCreated, .requestCreated, _):
            break

        case (.requestCreated, .frictionTimerStarted, _):
            state = .frictionWaiting

        case (.frictionWaiting, .evidenceRequired, true):
            state = .evidencePending

        case (.frictionWaiting, .evidenceRequired, false):
            state = .evidenceCompleted

        case (.evidencePending, .evidenceCompleted, _):
            state = .evidenceCompleted

        case (.evidenceCompleted, .aiReviewed, _):
            state = .aiReviewed

        case (.aiReviewed, .decisionApproved, _):
            state = .decisionApprovedTempUnlock

        case (.aiReviewed, .decisionDeferred, _):
            state = .decisionDeferred

        case (.aiReviewed, .decisionDenied, _):
            state = .decisionDenied

        case (.decisionApprovedTempUnlock, .sessionObserved, _):
            break

        case (.decisionApprovedTempUnlock, .sessionClosed, _):
            state = .sessionClosed

        case (.sessionClosed, .reviewLogged, _):
            state = .reviewLogged

        default:
            // Invalid transitions are ignored for safety in v1.
            break
        }
    }
}
