import VowCore
import Foundation

#if canImport(SwiftUI)
import SwiftUI

@MainActor
public final class UnlockRequestFlowCoordinator: ObservableObject {
    @Published public private(set) var stateMachine: UnlockRequestStateMachine
    @Published public var frictionSecondsRemaining: Double = 0
    @Published public private(set) var leaseManager: UnlockLeaseManager

    public let requestID: UUID
    public let target: BlockedTarget

    public private(set) var chaosEvidencePlan: ChaosHqEvidencePlan?

    private let onDecision: ((UnlockDecision) -> Void)?
    private let evidenceRunner: (@Sendable () async throws -> Bool)?

    private let frictionEngine: FrictionEngine
    private let frictionInputs: FrictionInputs
    private let approvedDurationSeconds: TimeInterval
    private let funnelMetricsRecorder: (any RequestFunnelMetricsRecorder)?

    private var frictionTimerTask: Task<Void, Never>?
    private var evidenceWork: Task<Void, Never>?
    private var frictionEndsAt: Date?

    private let nfcEnforcer: NfcRuntimeEnforcer?
    private let onNfcViolation: ((NfcViolation) -> Void)?


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
        funnelMetricsRecorder: (any RequestFunnelMetricsRecorder)? = nil,
        onDecision: ((UnlockDecision) -> Void)? = nil,
        nfcEnforcer: NfcRuntimeEnforcer? = nil,
        onNfcViolation: ((NfcViolation) -> Void)? = nil
    ) {
        self.stateMachine = UnlockRequestStateMachine(evidenceRequired: evidenceRequired)
        self.requestID = requestID
        self.target = target
        self.leaseManager = leaseManager
        self.chaosEvidencePlan = nil
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

        self.nfcEnforcer = nfcEnforcer
        self.onNfcViolation = onNfcViolation

        self.funnelMetricsRecorder = funnelMetricsRecorder
    }

    /// Convenience initializer that wires ChaosHQ mirror-intake into a VowCore
    /// evidence plan. v1: this currently only sets `evidenceRequired` and stores
    /// the plan for host-level execution/routing.
    public init(
        chaosMirrorIntakePayload: ChaosHqMirrorIntakePayload? = nil,
        chaosAdapter: any ChaosHqAdapter = DefaultChaosHqAdapter(),
        evidencePolicy: EvidencePolicy = EvidencePolicy(),
        requestID: UUID = UUID(),
        target: BlockedTarget,
        funnelMetricsRecorder: (any RequestFunnelMetricsRecorder)? = nil,
        onDecision: ((UnlockDecision) -> Void)? = nil,
        nfcEnforcer: NfcRuntimeEnforcer? = nil,
        onNfcViolation: ((NfcViolation) -> Void)? = nil
    ) {
        let plan: ChaosHqEvidencePlan? = chaosMirrorIntakePayload.flatMap { payload in
            do {
                return try chaosAdapter.mapMirrorIntake(
                    payload,
                    policy: evidencePolicy,
                    unlockRequestedAt: Date()
                )
            } catch {
                return nil
            }
        }

        let evidenceRequired = !(plan?.evidenceTaskInputs.isEmpty ?? true)

        self.stateMachine = UnlockRequestStateMachine(evidenceRequired: evidenceRequired)
        self.requestID = requestID
        self.target = target
        self.leaseManager = UnlockLeaseManager()
        self.chaosEvidencePlan = plan
        self.onDecision = onDecision
        self.evidenceRunner = nil
        self.frictionEngine = FrictionEngine()

        let computedTier: FrictionTier = {
            switch target.riskLevel {
            case .low: return .low
            case .medium: return .medium
            case .high: return .high
            }
        }()
        self.frictionInputs = FrictionInputs(tier: computedTier)
        self.approvedDurationSeconds = 300

        self.nfcEnforcer = nfcEnforcer
        self.onNfcViolation = onNfcViolation

        self.funnelMetricsRecorder = funnelMetricsRecorder
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

    private func record(_ event: UnlockRequestEvent) {
        guard let funnelMetricsRecorder = funnelMetricsRecorder else { return }
        funnelMetricsRecorder.record(
            event,
            requestID: requestID,
            evidenceRequired: stateMachine.evidenceRequired,
            riskTier: frictionInputs.tier,
            at: Date()
        )
    }

    @discardableResult
    private func applyAndRecord(_ event: UnlockRequestEvent) -> Bool {
        let prior = stateMachine.state
        stateMachine.apply(event)
        let changed = stateMachine.state != prior
        if changed {
            record(event)
        }
        return changed
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
            _ = applyAndRecord(.aiReviewed)

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
                    _ = self.applyAndRecord(.evidenceCompleted)
                    _ = self.applyAndRecord(.aiReviewed)
                    _ = self.applyAndRecord(.decisionDenied)
                }
            } catch {
                _ = self.applyAndRecord(.evidenceCompleted)
                _ = self.applyAndRecord(.aiReviewed)
                _ = self.applyAndRecord(.decisionDenied)
            }
        }
    }

    public func userStartedRequest() {
        frictionTimerTask?.cancel()
        frictionTimerTask = nil
        evidenceWork?.cancel()
        evidenceWork = nil

        _ = applyAndRecord(.requestCreated)
        _ = applyAndRecord(.frictionTimerStarted)

        let now = Date()
        let totalSeconds = frictionEngine.seconds(for: frictionInputs, now: now)
        frictionSecondsRemaining = totalSeconds
        frictionEndsAt = now.addingTimeInterval(totalSeconds)

        startFrictionTimerIfNeeded()
    }

    private func completeFrictionAsync() async {
        guard stateMachine.state == .frictionWaiting else { return }
        _ = applyAndRecord(.evidenceRequired)

        if stateMachine.state == .evidenceCompleted {
            // No evidence required; finish the AI review step.
            _ = applyAndRecord(.aiReviewed)
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
        _ = applyAndRecord(.evidenceCompleted)
        _ = applyAndRecord(.aiReviewed)
    }

    public func decisionApproved() {
        Task { await decisionApprovedAsync() }
    }

    private func decisionApprovedAsync() async {
        let now = Date()

        if let nfcEnforcer {
            do {
                let outcome = try await nfcEnforcer.verify(targetID: target.id, requestID: requestID, at: now)

                switch outcome {
                case .verified:
                    guard applyAndRecord(.decisionApproved) else { return }
                    grantLease(now: now)
                    onDecision?(.approved_temp_unlock)

                case .notVerified(let violation):
                    _ = applyAndRecord(.decisionDenied)
                    onNfcViolation?(violation)
                    onDecision?(.denied)
                }
            } catch {
                // Fail safe: deny unlock.
                let graceEndsAt = now.addingTimeInterval(nfcEnforcer.gracePeriodSeconds)
                let violation = NfcViolation(
                    targetID: target.id,
                    requestID: requestID,
                    detectedAt: now,
                    graceEndsAt: graceEndsAt,
                    alarmAt: graceEndsAt
                )

                _ = applyAndRecord(.decisionDenied)
                onNfcViolation?(violation)
                onDecision?(.denied)
            }

            return
        }

        guard applyAndRecord(.decisionApproved) else { return }
        grantLease(now: now)
        onDecision?(.approved_temp_unlock)
    }

    private func grantLease(now: Date) {
        let lease = UnlockLease(
            targetID: target.id,
            startAt: now,
            expiresAt: now.addingTimeInterval(approvedDurationSeconds),
            reason: "Temp unlock for request",
            requestID: requestID
        )
        _ = leaseManager.grant(lease, now: now)
    }

    public func decisionDeferred() {
        guard applyAndRecord(.decisionDeferred) else { return }
        onDecision?(.deferred)
    }

    public func decisionDenied() {
        guard applyAndRecord(.decisionDenied) else { return }
        onDecision?(.denied)
    }

    public func sessionObserved() {
        _ = applyAndRecord(.sessionObserved)
    }

    public func sessionClosed() {
        _ = applyAndRecord(.sessionClosed)
    }

    public func reviewLogged() {
        _ = applyAndRecord(.reviewLogged)
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

            Button("Defer") {
                coordinator.decisionDeferred()
            }

            Button("Deny") {
                coordinator.decisionDenied()
            }
        }
        .padding()
    }
}

#endif
