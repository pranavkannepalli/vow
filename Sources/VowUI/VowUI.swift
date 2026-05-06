import VowCore

#if canImport(SwiftUI)
import SwiftUI

public enum VowUI {
    public static func shieldInterceptionView(
        target: BlockedTarget,
        evidenceRequired: Bool,
        onDecision: ((UnlockDecision) -> Void)? = nil,
        nfcEnforcer: NfcRuntimeEnforcer? = nil,
        onNfcViolation: ((NfcViolation) -> Void)? = nil
    ) -> ShieldInterceptionView {
        ShieldInterceptionView(
            target: target,
            evidenceRequired: evidenceRequired,
            onDecision: onDecision,
            nfcEnforcer: nfcEnforcer,
            onNfcViolation: onNfcViolation
        )
    }
}

#else

public enum VowUI {
    // SwiftUI isn't available in this build environment.
}

#endif
