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

    public let nfcEnforcer: NfcRuntimeEnforcer?
    public let onNfcViolation: ((NfcViolation) -> Void)?

    @State private var mode: Mode = .shield

    public init(
        target: BlockedTarget,
        evidenceRequired: Bool,
        onDecision: ((UnlockDecision) -> Void)? = nil,
        nfcEnforcer: NfcRuntimeEnforcer? = nil,
        onNfcViolation: ((NfcViolation) -> Void)? = nil
    ) {
        self.target = target
        self.evidenceRequired = evidenceRequired
        self.onDecision = onDecision
        self.nfcEnforcer = nfcEnforcer
        self.onNfcViolation = onNfcViolation
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
                nfcEnforcer: nfcEnforcer,
                onNfcViolation: onNfcViolation
            )

            UnlockRequestFlowView(coordinator: coordinator)
        }
    }
}

#endif
