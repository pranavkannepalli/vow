import VowCore

#if canImport(SwiftUI)
import SwiftUI

/// v1: UI-level shield interception (Screen Time/ManagedSettings wiring intentionally not included yet).
public struct ShieldInterceptionView: View {
    public enum Mode {
        case shield
        case unlockRequest
    }

    public let target: BlockedTarget
    public let evidenceRequired: Bool
    public let onDecision: ((UnlockDecision) -> Void)?
    private let nfcEnforcer: NfcRuntimeEnforcer?

    @State private var mode: Mode = .shield

    public init(
        target: BlockedTarget,
        evidenceRequired: Bool,
        onDecision: ((UnlockDecision) -> Void)? = nil,
        nfcEnforcer: NfcRuntimeEnforcer? = nil
    ) {
        self.target = target
        self.evidenceRequired = evidenceRequired
        self.onDecision = onDecision
        self.nfcEnforcer = nfcEnforcer
    }

    public var body: some View {
        switch mode {
        case .shield:
            ShieldView(
                label: target.label,
                riskLevel: target.riskLevel,
                onRequestUnlock: {
                    mode = .unlockRequest
                }
            )

        case .unlockRequest:
            let coordinator = UnlockRequestFlowCoordinator(
                evidenceRequired: evidenceRequired,
                target: target,
                onDecision: onDecision,
                nfcEnforcer: nfcEnforcer
            )

            UnlockRequestFlowView(coordinator: coordinator)
        }
    }
}

#endif
