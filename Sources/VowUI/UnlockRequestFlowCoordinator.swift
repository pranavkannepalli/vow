import VowCore
import Foundation

#if canImport(SwiftUI)
import SwiftUI

@MainActor
public final class UnlockRequestFlowCoordinator: ObservableObject {
    @Published public private(set) var stateMachine: UnlockRequestStateMachine
    @Published public var frictionSecondsRemaining: Double = 0

    public let requestID: UUID
    public let target: BlockedTarget

    public private(set) var chaosEvidencePlan: ChaosHqEvidencePlan?

    private let onDecision: ((UnlockDecision) -> Void)?

    public init(
        evidenceRequired: Bool,
        requestID: UUID = UUID(),
        target: BlockedTarget,
        onDecision: ((UnlockDecision) -> Void)? = nil
    ) {
        self.stateMachine = UnlockRequestStateMachine(evidenceRequired: evidenceRequired)
        self.requestID = requestID
        self.target = target
        self.chaosEvidencePlan = nil
        self.onDecision = onDecision
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
        onDecision: ((UnlockDecision) -> Void)? = nil
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
        self.chaosEvidencePlan = plan
        self.onDecision = onDecision
    }

    public func userStartedRequest() {
        stateMachine.apply(.requestCreated)
        stateMachine.apply(.frictionTimerStarted)
    }

    /// v1 placeholder: real implementation should start a timer and transition when it completes.
    public func completeFriction() {
        if stateMachine.evidenceRequired {
            stateMachine.apply(.evidenceRequired)
        } else {
            stateMachine.apply(.evidenceCompleted)
        }
    }

    public func markEvidenceCompleted() {
        stateMachine.apply(.evidenceCompleted)
        stateMachine.apply(.aiReviewed)
    }

    public func decisionApproved() {
        stateMachine.apply(.decisionApproved)
        onDecision?(.approved_temp_unlock)
    }

    public func decisionDeferred() {
        stateMachine.apply(.decisionDeferred)
        onDecision?(.deferred)
    }

    public func decisionDenied() {
        stateMachine.apply(.decisionDenied)
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
