import Foundation
import VowCore

/// v1: app-blocking/shield configuration entry point.
/// This is intentionally backend-abstracted so ManagedSettings wiring can be added later.
public final class ShieldConfigurationController {
    private let backend: ShieldConfigurationBackend
    private let requiredExtensionBundleIdentifiers: [String]

    /// - Note: This is host-app side gating. Provide the bundle identifiers you expect to be present for the Screen Time stack.
    ///   If authorization/extensions are not verified, `setPolicy` becomes a no-op (prevents unsafe partial enablement).
    public init(
        backend: ShieldConfigurationBackend = NoopShieldConfigurationBackend(),
        requiredExtensionBundleIdentifiers: [String] = []
    ) {
        self.backend = backend
        self.requiredExtensionBundleIdentifiers = requiredExtensionBundleIdentifiers
    }

    public func setPolicy(_ policy: BlockedTargetsPolicy) {
        let report = FamilyControlsCapabilityGate.verify(
            requiredExtensionBundleIdentifiers: requiredExtensionBundleIdentifiers
        )
        guard report.isReady else {
            // Intentionally no-op: we avoid entering a partially-enabled unsafe state.
            return
        }
        backend.apply(policy: policy)
    }

    public func reset() {
        backend.clear()
    }
}

