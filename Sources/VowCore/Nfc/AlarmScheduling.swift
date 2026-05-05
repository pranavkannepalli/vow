import Foundation

/// Enforces an NFC-based denial by scheduling an enforcement "alarm".
///
/// In production this would likely route into an OS-level or app-level
/// notification / telemetry pathway.
public protocol AlarmScheduling: Sendable {
    func scheduleEnforcementAlarm(
        targetID: UUID,
        requestID: UUID,
        violation: NfcViolation,
        now: Date,
        gracePeriodSeconds: TimeInterval
    ) async throws
}

/// Default no-op scheduler for tests and non-iOS environments.
public struct NoopAlarmScheduler: AlarmScheduling {
    public init() {}

    public func scheduleEnforcementAlarm(
        targetID: UUID,
        requestID: UUID,
        violation: NfcViolation,
        now: Date,
        gracePeriodSeconds: TimeInterval
    ) async throws {
        // intentionally no-op
    }
}

/// A violation outcome produced by NFC runtime verification.
public enum NfcViolation: String, Codable, Hashable, Sendable {
    /// NFC read failed and/or the presented fingerprint is not enrolled.
    case notVerified
}
