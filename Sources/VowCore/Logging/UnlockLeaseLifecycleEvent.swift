import Foundation

/// Telemetry-safe events for the temporary-unlock lease lifecycle.
///
/// Data minimization: payload uses only UUID identifiers + coarse timestamps.
public enum UnlockLeaseLifecycleEvent: Codable, Hashable, Sendable {
    case leaseGranted(LeaseGrantedPayload)
    case leaseExtended(LeaseExtendedPayload)
    case leaseExpired(LeaseExpiredPayload)
    case leaseReshielded(LeaseReshieldedPayload)

    public struct LeaseGrantedPayload: Codable, Hashable, Sendable {
        public let leaseID: UUID
        public let targetID: UUID
        public let requestID: UUID
        public let startAt: Date
        public let expiresAt: Date
        public let at: Date

        public init(leaseID: UUID, targetID: UUID, requestID: UUID, startAt: Date, expiresAt: Date, at: Date) {
            self.leaseID = leaseID
            self.targetID = targetID
            self.requestID = requestID
            self.startAt = startAt
            self.expiresAt = expiresAt
            self.at = at
        }
    }

    public struct LeaseExtendedPayload: Codable, Hashable, Sendable {
        public let leaseID: UUID
        public let targetID: UUID
        public let requestID: UUID
        public let previousExpiresAt: Date
        public let newExpiresAt: Date
        public let at: Date

        public init(
            leaseID: UUID,
            targetID: UUID,
            requestID: UUID,
            previousExpiresAt: Date,
            newExpiresAt: Date,
            at: Date
        ) {
            self.leaseID = leaseID
            self.targetID = targetID
            self.requestID = requestID
            self.previousExpiresAt = previousExpiresAt
            self.newExpiresAt = newExpiresAt
            self.at = at
        }
    }

    public struct LeaseExpiredPayload: Codable, Hashable, Sendable {
        public let leaseID: UUID
        public let targetID: UUID
        public let requestID: UUID
        public let startAt: Date
        public let expiresAt: Date
        public let at: Date

        public init(leaseID: UUID, targetID: UUID, requestID: UUID, startAt: Date, expiresAt: Date, at: Date) {
            self.leaseID = leaseID
            self.targetID = targetID
            self.requestID = requestID
            self.startAt = startAt
            self.expiresAt = expiresAt
            self.at = at
        }
    }

    public struct LeaseReshieldedPayload: Codable, Hashable, Sendable {
        public let reshieldTargetIDs: [UUID]
        public let at: Date

        public init(reshieldTargetIDs: [UUID], at: Date) {
            self.reshieldTargetIDs = reshieldTargetIDs
            self.at = at
        }
    }
}

/// Host-facing sink for lease lifecycle telemetry.
public protocol LeaseLifecycleMetricsRecorder: Sendable {
    func record(_ event: UnlockLeaseLifecycleEvent)
}

public struct NoopLeaseLifecycleMetricsRecorder: LeaseLifecycleMetricsRecorder {
    public init() {}
    public func record(_ event: UnlockLeaseLifecycleEvent) {}
}
