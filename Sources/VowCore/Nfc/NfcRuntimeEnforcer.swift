import Foundation

public enum NfcVerificationResult: Codable, Hashable, Sendable {
    case verified
    case notVerified(NfcViolation)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)

        switch raw {
        case "verified":
            self = .verified
        default:
            // Backwards/forwards-compatible minimal decoding.
            self = .notVerified(.notVerified)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .verified:
            try container.encode("verified")
        case .notVerified:
            try container.encode("notVerified")
        }
    }
}

/// Runtime enforcement brain for NFC verification.
///
/// Fail-safe behavior: any verifier error is treated as "not verified".
public struct NfcRuntimeEnforcer: Sendable {
    private let targetID: UUID
    private let verifier: @Sendable () async throws -> Bool
    private let scheduler: any AlarmScheduling
    private let gracePeriodSeconds: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        targetID: UUID,
        verifier: @escaping @Sendable () async throws -> Bool,
        scheduler: any AlarmScheduling,
        gracePeriodSeconds: TimeInterval,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.targetID = targetID
        self.verifier = verifier
        self.scheduler = scheduler
        self.gracePeriodSeconds = gracePeriodSeconds
        self.now = now
    }

    /// Verifies the presented NFC card for this enforcer's `targetID`.
    ///
    /// - Important: This never allows unlock on verifier errors.
    public func verify(requestID: UUID) async -> NfcVerificationResult {
        let violation: NfcViolation = .notVerified

        do {
            let verified = try await verifier()
            if verified {
                return .verified
            }

            // Not verified => schedule enforcement and deny.
            try? await scheduler.scheduleEnforcementAlarm(
                targetID: targetID,
                requestID: requestID,
                violation: violation,
                now: now(),
                gracePeriodSeconds: gracePeriodSeconds
            )
            return .notVerified(violation)
        } catch {
            // Fail-safe: verifier errors are treated as "not verified".
            try? await scheduler.scheduleEnforcementAlarm(
                targetID: targetID,
                requestID: requestID,
                violation: violation,
                now: now(),
                gracePeriodSeconds: gracePeriodSeconds
            )
            return .notVerified(violation)
        }
    }
}
