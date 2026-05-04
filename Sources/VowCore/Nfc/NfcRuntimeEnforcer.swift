import Foundation

/// Schedules local/OS notifications that act as "enforcement" triggers.
///
/// iOS implementations would typically wire into `UNUserNotificationCenter`
/// or Alarm/Calendar frameworks. In non-iOS environments (including unit
/// tests), you can provide a mock scheduler.
public protocol AlarmScheduling {
    func scheduleAlarm(at date: Date, payload: AlarmPayload) async throws
}

/// Payload delivered to the alarm scheduler.
public struct AlarmPayload: Codable, Hashable {
    public let violation: NfcViolation

    public init(violation: NfcViolation) {
        self.violation = violation
    }
}

/// What it means when an NFC-gated unlock was not properly verified.
public struct NfcViolation: Codable, Hashable {
    public let targetID: UUID
    public let requestID: UUID

    /// When the system determined NFC wasn’t presented (or verification
    /// failed).
    public let detectedAt: Date

    /// The end of the grace period.
    public let graceEndsAt: Date

    /// When the enforcement alarm should fire (host can reshield/revoke).
    public let alarmAt: Date

    public init(
        targetID: UUID,
        requestID: UUID,
        detectedAt: Date,
        graceEndsAt: Date,
        alarmAt: Date
    ) {
        self.targetID = targetID
        self.requestID = requestID
        self.detectedAt = detectedAt
        self.graceEndsAt = graceEndsAt
        self.alarmAt = alarmAt
    }
}

/// Result of attempting NFC verification.
public enum NfcVerificationOutcome: Equatable {
    case verified
    case notVerified(NfcViolation)
}

/// Runs NFC verification and (if needed) schedules an enforcement alarm.
public struct NfcRuntimeEnforcer {
    public let verifier: @Sendable () async throws -> Bool
    public let scheduler: any AlarmScheduling
    public let gracePeriodSeconds: TimeInterval

    private let now: @Sendable () -> Date

    public init(
        verifier: @Sendable @escaping () async throws -> Bool,
        scheduler: any AlarmScheduling,
        gracePeriodSeconds: TimeInterval,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.verifier = verifier
        self.scheduler = scheduler
        self.gracePeriodSeconds = gracePeriodSeconds
        self.now = now
    }

    public func verify(
        targetID: UUID,
        requestID: UUID,
        at date: Date? = nil
    ) async throws -> NfcVerificationOutcome {
        let detectedAt = date ?? now()
        let verified = (try await verifier())

        guard verified == false else {
            return .verified
        }

        let graceEndsAt = detectedAt.addingTimeInterval(gracePeriodSeconds)
        let alarmAt = graceEndsAt

        let violation = NfcViolation(
            targetID: targetID,
            requestID: requestID,
            detectedAt: detectedAt,
            graceEndsAt: graceEndsAt,
            alarmAt: alarmAt
        )

        try await scheduler.scheduleAlarm(at: alarmAt, payload: .init(violation: violation))
        return .notVerified(violation)
    }
}

/// Default scheduler that does nothing (useful for non-iOS builds).
public struct NoopAlarmScheduler: AlarmScheduling {
    public init() {}

    public func scheduleAlarm(at date: Date, payload: AlarmPayload) async throws {
        // no-op
        _ = (date, payload)
    }
}
