import Foundation

public protocol RequestLifecycleLogger {
    func log(_ event: String, requestID: UUID, metadata: [String: String]?)
}

/// Convenience wrapper that can attach ChaosHQ identifiers to unlock request logs.
///
/// The core state machine code only needs a generic logger; this wrapper ensures
/// chaos task/execution IDs are always included in the metadata for unlock events.
public struct RequestLogger: RequestLifecycleLogger {
    public let delegate: RequestLifecycleLogger

    public init(delegate: RequestLifecycleLogger = NoopRequestLifecycleLogger()) {
        self.delegate = delegate
    }

    public func log(_ event: String, requestID: UUID, metadata: [String : String]?) {
        delegate.log(event, requestID: requestID, metadata: metadata)
    }

    public func logUnlockEvent(
        _ event: String,
        requestID: UUID,
        chaosTaskID: UUID?,
        chaosExecutionID: UUID?,
        metadata: [String: String]? = nil
    ) {
        var merged = metadata ?? [:]
        if let chaosTaskID {
            merged["chaosTaskID"] = chaosTaskID.uuidString
        }
        if let chaosExecutionID {
            merged["chaosExecutionID"] = chaosExecutionID.uuidString
        }

        log(event, requestID: requestID, metadata: merged.isEmpty ? nil : merged)
    }
}

public struct NoopRequestLifecycleLogger: RequestLifecycleLogger {
    public init() {}
    public func log(_ event: String, requestID: UUID, metadata: [String : String]?) {}
}
