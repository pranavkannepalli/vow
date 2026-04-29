import Foundation

public struct BlockedTargetsPolicy: Codable, Hashable {
    public var targets: [BlockedTarget]

    public init(targets: [BlockedTarget] = []) {
        self.targets = targets
    }
}

/// v1: abstraction for the platform Screen Time / ManagedSettings backend.
public protocol ShieldConfigurationBackend {
    func apply(policy: BlockedTargetsPolicy)
    func clear()
}

public struct NoopShieldConfigurationBackend: ShieldConfigurationBackend {
    public init() {}
    public func apply(policy: BlockedTargetsPolicy) {}
    public func clear() {}
}
