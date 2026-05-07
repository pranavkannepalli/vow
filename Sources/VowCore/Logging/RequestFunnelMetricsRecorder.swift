import Foundation

/// Records unlock-request “funnel” events for QA/instrumentation.
///
/// This is intentionally lightweight: host apps can implement it to forward
/// events into their analytics stack.
public protocol RequestFunnelMetricsRecorder: Sendable {
    func record(
        _ event: UnlockRequestEvent,
        requestID: UUID,
        evidenceRequired: Bool,
        riskTier: FrictionTier,
        at date: Date
    )
}

public struct NoopRequestFunnelMetricsRecorder: RequestFunnelMetricsRecorder {
    public init() {}
    public func record(
        _ event: UnlockRequestEvent,
        requestID: UUID,
        evidenceRequired: Bool,
        riskTier: FrictionTier,
        at date: Date
    ) {}
}
