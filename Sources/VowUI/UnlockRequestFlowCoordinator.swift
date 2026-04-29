import VowCore

#if canImport(SwiftUI)
import SwiftUI

@MainActor
public final class UnlockRequestFlowCoordinator: ObservableObject {
    @Published public private(set) var stateMachine: UnlockRequestStateMachine
    @Published public var frictionSecondsRemaining: Double = 0

    public let requestID: UUID
    public let target: BlockedTarget

    public init(
        evidenceRequired: Bool,
        requestID: UUID = UUID(),
        target: BlockedTarget
    ) {
        self.stateMachine = UnlockRequestStateMachine(evidenceRequired: evidenceRequired)
        self.requestID = requestID
        self.target = target
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
            stateMachine.apply(.evidenceRequired)
        }
    }

    public func markEvidenceCompleted() {
        stateMachine.apply(.evidenceCompleted)
        stateMachine.apply(.aiReviewed)
    }

    public func decisionApproved() {
        stateMachine.apply(.decisionApproved)
    }

    public func decisionDenied() {
        stateMachine.apply(.decisionDenied)
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
        }
        .padding()
    }
}

#endif
