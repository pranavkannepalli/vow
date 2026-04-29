import VowCore

#if canImport(SwiftUI)
import SwiftUI

@MainActor
public final class UnlockRequestFlowCoordinator: ObservableObject {
    @Published public private(set) var stateMachine: UnlockRequestStateMachine
    @Published public var frictionSecondsRemaining: Double = 0
    @Published public private(set) var leaseManager: UnlockLeaseManager

    public let requestID: UUID
    public let target: BlockedTarget

    private let onDecision: ((UnlockDecision) -> Void)?
    private let evidenceRunner: (@Sendable () async throws -> Bool)?

    private let frictionEngine: FrictionEngine
    private let frictionInputs: FrictionInputs
    private let approvedDurationSeconds: TimeInterval

    private var frictionTimerTask: Task<Void, Never>?
    private var evidenceWork: Task<Void, Never>?
    private var frictionEndsAt: Date?

    public struct UnlockRequestFlowSnapshot: Codable {
        public var requestID: UUID
        public var target: BlockedTarget
        public var evidenceRequired: Bool
        public var state: RequestState
        public var frictionEndsAt: Date?
        public var leaseManager: UnlockLeaseManager
    }

    public init(
        evidenceRequired: Bool,
        requestID: UUID = UUID(),
        target: BlockedTarget,
        leaseManager: UnlockLeaseManager = UnlockLeaseManager(),
        approvedDurationSeconds: TimeInterval = 300,
        frictionEngine: FrictionEngine = FrictionEngine(),
        frictionInputs: FrictionInputs? = nil,
        evidenceRunner: (@Sendable () async throws -> Bool)? = nil,
        onDecision: ((UnlockDecision) -> Void)? = nil
    ) {
        self.stateMachine = UnlockRequestStateMachine(evidenceRequired: evidenceRequired)
        self.requestID = requestID
        self.target = target
        self.leaseManager = leaseManager
        self.onDecision = onDecision
        self.evidenceRunner = evidenceRunner
        self.frictionEngine = frictionEngine

        let computedTier: FrictionTier = {
            switch target.riskLevel {
            case .low: return .low
            case .medium: return .medium
            case .high: return .high
            }
        }()
        self.frictionInputs = frictionInputs ?? FrictionInputs(tier: computedTier)
        self.approvedDurationSeconds = approvedDurationSeconds
    }

    public func snapshot() -> UnlockRequestFlowSnapshot {
        UnlockRequestFlowSnapshot(
            requestID: requestID,
            target: target,
            evidenceRequired: stateMachine.evidenceRequired,
            state: stateMachine.state,
            frictionEndsAt: frictionEndsAt,
            leaseManager: leaseManager
        )
    }

    public static func restore(
        from snapshot: UnlockRequestFlowSnapshot,
        approvedDurationSeconds: TimeInterval = 300,
        frictionEngine: FrictionEngine = FrictionEngine(),
        frictionInputs: FrictionInputs? = nil,
        evidenceRunner: (@Sendable () async throws -> Bool)? = nil,
        onDecision: ((UnlockDecision) -> Void)? = nil
    ) -> UnlockRequestFlowCoordinator {
        let coordinator = UnlockRequestFlowCoordinator(
            evidenceRequired: snapshot.evidenceRequired,
            requestID: snapshot.requestID,
            target: snapshot.target,
            leaseManager: snapshot.leaseManager,
            approvedDurationSeconds: approvedDurationSeconds,
            frictionEngine: frictionEngine,
            frictionInputs: frictionInputs,
            evidenceRunner: evidenceRunner,
            onDecision: onDecision
        )

        coordinator.stateMachine = UnlockRequestStateMachine(
            evidenceRequired: snapshot.evidenceRequired,
            startingState: snapshot.state
        )
        coordinator.frictionEndsAt = snapshot.frictionEndsAt
        coordinator.frictionSecondsRemaining = snapshot.frictionEndsAt.map { max(0, $0.timeIntervalSinceNow) } ?? 0

        coordinator.startAppropriateWorkAfterRestore()
        return coordinator
    }

    private func startAppropriateWorkAfterRestore() {
        switch stateMachine.state {
        case .requestCreated:
            break

        case .frictionWaiting:
            startFrictionTimerIfNeeded()

        case .evidencePending:
            startEvidenceIfNeeded()

        case .evidenceCompleted:
            stateMachine.apply(.aiReviewed)

        case .aiReviewed:
            break

        case .decisionApprovedTempUnlock, .decisionDeferred, .decisionDenied, .sessionClosed, .reviewLogged:
            break
        }
    }

    private func startFrictionTimerIfNeeded() {
        frictionTimerTask?.cancel()
        frictionTimerTask = nil

        guard stateMachine.state == .frictionWaiting else { return }
        guard let endAt = frictionEndsAt else { return }

        let remaining = max(0, endAt.timeIntervalSinceNow)
        frictionSecondsRemaining = remaining

        guard remaining > 0 else {
            Task { await completeFrictionAsync() }
            return
        }

        frictionTimerTask = Task { [weak self] in
            guard let self else { return }
            let nanos = UInt64(remaining * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            await self.completeFrictionAsync()
        }
    }

    private func startEvidenceIfNeeded() {
        evidenceWork?.cancel()
        evidenceWork = nil

        guard stateMachine.state == .evidencePending else { return }

        evidenceWork = Task { [weak self] in
            guard let self else { return }
            do {
                let completed: Bool
                if let evidenceRunner = self.evidenceRunner {
                    completed = try await evidenceRunner()
                } else {
                    completed = true
                }

                if completed {
                    self.markEvidenceCompleted()
                } else {
                    // Scaffold behavior: treat evidence failure as terminal denial.
                    self.stateMachine.apply(.evidenceCompleted)
                    self.stateMachine.apply(.aiReviewed)
                    self.stateMachine.apply(.decisionDenied)
                }
            } catch {
                self.stateMachine.apply(.evidenceCompleted)
                self.stateMachine.apply(.aiReviewed)
                self.stateMachine.apply(.decisionDenied)
            }
        }
    }

    public func userStartedRequest() {
        frictionTimerTask?.cancel()
        frictionTimerTask = nil
        evidenceWork?.cancel()
        evidenceWork = nil

        stateMachine.apply(.requestCreated)
        stateMachine.apply(.frictionTimerStarted)

        let now = Date()
        let totalSeconds = frictionEngine.seconds(for: frictionInputs, now: now)
        frictionSecondsRemaining = totalSeconds
        frictionEndsAt = now.addingTimeInterval(totalSeconds)

        startFrictionTimerIfNeeded()
    }

    private func completeFrictionAsync() async {
        guard stateMachine.state == .frictionWaiting else { return }
        stateMachine.apply(.evidenceRequired)

        if stateMachine.state == .evidenceCompleted {
            // No evidence required; finish the AI review step.
            stateMachine.apply(.aiReviewed)
            return
        }

        startEvidenceIfNeeded()
    }

    /// Backwards-compatible API for UI/tests.
    public func completeFriction() {
        frictionTimerTask?.cancel()
        frictionTimerTask = nil
        frictionSecondsRemaining = 0
        frictionEndsAt = nil
        Task { await completeFrictionAsync() }
    }

    public func markEvidenceCompleted() {
        stateMachine.apply(.evidenceCompleted)
        stateMachine.apply(.aiReviewed)
    }

    public func decisionApproved() {
        let prior = stateMachine.state
        stateMachine.apply(.decisionApproved)
        guard stateMachine.state != prior else { return }

        let now = Date()
        let lease = UnlockLease(
            targetID: target.id,
            startAt: now,
            expiresAt: now.addingTimeInterval(approvedDurationSeconds),
            reason: "Temp unlock for request",
            requestID: requestID
        )
        _ = leaseManager.grant(lease, now: now)
        onDecision?(.approved_temp_unlock)
    }

    public func decisionDeferred() {
        let prior = stateMachine.state
        stateMachine.apply(.decisionDeferred)
        guard stateMachine.state != prior else { return }
        onDecision?(.deferred)
    }

    public func decisionDenied() {
        let prior = stateMachine.state
        stateMachine.apply(.decisionDenied)
        guard stateMachine.state != prior else { return }
        onDecision?(.denied)
    }
}

public struct UnlockRequestFlowView: View {
    @StateObject private var coordinator: UnlockRequestFlowCoordinator

    public init(coordinator: UnlockRequestFlowCoordinator) {
        _coordinator = StateObject(wrappedValue: coordinator)
    }

    public var body: some View {
        VStack(spacing: 12) {
            Text("Unlock Request")
                .font(.headline)

            Text("State: \(coordinator.stateMachine.state.rawValue)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if coordinator.stateMachine.state == .frictionWaiting {
                Text("Friction remaining: \(Int(coordinator.frictionSecondsRemaining))s")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("Start") {
                coordinator.userStartedRequest()
            }

            Button("Approve") {
                coordinator.decisionApproved()
            }
        }
        .padding()
    }
}

#endif
