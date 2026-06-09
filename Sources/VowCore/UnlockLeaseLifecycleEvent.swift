import Foundation

/// Privacy-safe instrumentation events for temporary unlock leases.
///
/// Intended usage:
/// - Host/mobile layer forwards these events into analytics.
/// - Do **not** include user-identifying or sensitive child data in `reason`.
///   Prefer coarse categorization (or omit by passing an empty/coarse string).
public enum UnlockLeaseLifecycleEventType: String, Codable, Hashable {
    /// A brand-new lease was granted.
    case leaseGranted
    /// An existing active lease for the same target was extended (mergeActive).
    case leaseExtended
    /// One or more previously-active leases expired.
    case leaseExpired
    /// The caller reconciled and reshielded targets whose leases expired.
    case leaseReshielded
}

/// A single, privacy-safe event for lease lifecycle tracking.
public struct UnlockLeaseLifecycleEvent: Codable, Hashable {
    public let type: UnlockLeaseLifecycleEventType
    public let occurredAt: Date

    /// Identifiers used for correlation. These are UUIDs (not personal data).
    public let requestID: UUID?
    public let leaseID: UUID?
    public let targetID: UUID?

    /// Lease timing (useful for debugging and analytics).
    public let startAt: Date?
    public let expiresAt: Date?

    /// Coarse reason text describing why the unlock was granted.
    /// Privacy note: host should avoid embedding sensitive personal/child data.
    public let reason: String?

    /// Aggregated reconciliation details for reshield events.
    public let reshieldedTargetIDs: [UUID]?
    public let expiredLeaseIDs: [UUID]?

    public init(
        type: UnlockLeaseLifecycleEventType,
        occurredAt: Date,
        requestID: UUID? = nil,
        leaseID: UUID? = nil,
        targetID: UUID? = nil,
        startAt: Date? = nil,
        expiresAt: Date? = nil,
        reason: String? = nil,
        reshieldedTargetIDs: [UUID]? = nil,
        expiredLeaseIDs: [UUID]? = nil
    ) {
        self.type = type
        self.occurredAt = occurredAt
        self.requestID = requestID
        self.leaseID = leaseID
        self.targetID = targetID
        self.startAt = startAt
        self.expiresAt = expiresAt
        self.reason = reason
        self.reshieldedTargetIDs = reshieldedTargetIDs
        self.expiredLeaseIDs = expiredLeaseIDs
    }
}
