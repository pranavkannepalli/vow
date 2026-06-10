import Foundation

/// Privacy-minimized telemetry for temporary unlock lease lifecycle.
///
/// IMPORTANT: Payloads intentionally include only non-sensitive UUID/time fields.
public enum UnlockLeaseLifecycleEvent: Codable, Equatable {
    case leaseGranted(LeaseGrantedPayload)
    case leaseExtended(LeaseExtendedPayload)
    case leaseExpired(LeaseExpiredPayload)
    case leaseReshielded(LeaseReshieldedPayload)

    public struct LeaseGrantedPayload: Codable, Equatable {
        public let leaseID: UUID
        public let targetID: UUID
        public let requestID: UUID
        public let startAt: Date
        public let expiresAt: Date
        public let at: Date

        public init(
            leaseID: UUID,
            targetID: UUID,
            requestID: UUID,
            startAt: Date,
            expiresAt: Date,
            at: Date
        ) {
            self.leaseID = leaseID
            self.targetID = targetID
            self.requestID = requestID
            self.startAt = startAt
            self.expiresAt = expiresAt
            self.at = at
        }
    }

    public struct LeaseExtendedPayload: Codable, Equatable {
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

    public struct LeaseExpiredPayload: Codable, Equatable {
        public let leaseID: UUID
        public let targetID: UUID
        public let requestID: UUID
        public let startAt: Date
        public let expiresAt: Date
        public let at: Date

        public init(
            leaseID: UUID,
            targetID: UUID,
            requestID: UUID,
            startAt: Date,
            expiresAt: Date,
            at: Date
        ) {
            self.leaseID = leaseID
            self.targetID = targetID
            self.requestID = requestID
            self.startAt = startAt
            self.expiresAt = expiresAt
            self.at = at
        }
    }

    public struct LeaseReshieldedPayload: Codable, Equatable {
        public let reshieldTargetIDs: [UUID]
        public let at: Date

        public init(reshieldTargetIDs: [UUID], at: Date) {
            self.reshieldTargetIDs = reshieldTargetIDs
            self.at = at
        }
    }
}
