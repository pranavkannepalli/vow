import Foundation
import VowCore

/// v1: app-blocking/shield configuration entry point.
/// This is intentionally backend-abstracted so ManagedSettings wiring can be added later.
public final class ShieldConfigurationController {
    private let backend: ShieldConfigurationBackend

    public init(backend: ShieldConfigurationBackend = NoopShieldConfigurationBackend()) {
        self.backend = backend
    }

    public func setPolicy(_ policy: BlockedTargetsPolicy) {
        backend.apply(policy: policy)
    }

    public func reset() {
        backend.clear()
    }
}
