import Foundation

/// Manages temporary unlock leases and determines which targets need to be
/// "reshielded" once leases expire.
///
/// This is intentionally UI/ScreenTime-agnostic: the caller can translate
/// returned targetIDs into ManagedSettings shield updates.
public struct UnlockLeaseManager: Codable, Hashable {
    public var leases: [UnlockLease]

    /// The set of lease IDs that were considered active the last time the caller
    /// reconciled expiry. Used to detect which leases newly expired.
    ///
    /// Note: this is derived from `leases` and is not persisted across Codable
    /// encoding. After decoding, we conservatively recompute using `Date()`.
    private var activeLeaseIDs: Set<UUID>

    private enum CodingKeys: String, CodingKey {
        case leases
    }

    public init(leases: [UnlockLease] = [], now: Date = Date()) {
        self.leases = leases
        self.activeLeaseIDs = Set(leases.filter { $0.isActive(at: now) }.map { $0.id })
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.leases = try container.decode([UnlockLease].self, forKey: .leases)
        self.activeLeaseIDs = Set(leases.filter { $0.isActive(at: Date()) }.map { $0.id })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(leases, forKey: .leases)
    }

    /// Returns true if there is an active lease for `targetID` at `now`.
    public func isTemporarilyUnlocked(targetID: UUID, at now: Date = Date()) -> Bool {
        leases.contains { $0.targetID == targetID && $0.isActive(at: now) }
    }

    /// Grants a new lease.
    ///
    /// If `mergeActive` is true and there is already an active lease for the
    /// same `targetID`, the lease is merged by extending `expiresAt` to the
    /// latest expiry. The lease `id` and original `startAt` are preserved.
    @discardableResult
    public mutating func grant(
        _ lease: UnlockLease,
        mergeActive: Bool = true,
        now: Date = Date(),
        record: ((UnlockLeaseLifecycleEvent) -> Void)? = nil
    ) -> UnlockLease {
        if mergeActive,
           let idx = leases.firstIndex(where: { $0.targetID == lease.targetID && $0.isActive(at: now) }),
           lease.isActive(at: now) {
            let existing = leases[idx]
            let extendedExpiresAt = max(existing.expiresAt, lease.expiresAt)
            let merged = UnlockLease(
                id: existing.id,
                targetID: existing.targetID,
                startAt: existing.startAt,
                expiresAt: extendedExpiresAt,
                reason: lease.reason,
                requestID: lease.requestID
            )
            leases[idx] = merged

            if merged.isActive(at: now) {
                activeLeaseIDs.insert(merged.id)
            }

            record?(UnlockLeaseLifecycleEvent(
                type: .leaseExtended,
                occurredAt: now,
                requestID: merged.requestID,
                leaseID: merged.id,
                targetID: merged.targetID,
                startAt: merged.startAt,
                expiresAt: merged.expiresAt,
                reason: merged.reason
            ))

            return merged
        } else {
            leases.append(lease)
            if lease.isActive(at: now) {
                activeLeaseIDs.insert(lease.id)
            }

            record?(UnlockLeaseLifecycleEvent(
                type: .leaseGranted,
                occurredAt: now,
                requestID: lease.requestID,
                leaseID: lease.id,
                targetID: lease.targetID,
                startAt: lease.startAt,
                expiresAt: lease.expiresAt,
                reason: lease.reason
            ))

            return lease
        }
    }

    /// Reconciles which leases are expired as of `now`.
    ///
    /// - Removes expired leases from `leases`.
    /// - Returns the targetIDs whose leases newly expired since the last
    ///   reconciliation, so callers can reshield those targets.
    ///
    /// If `record` is provided, emits privacy-safe instrumentation events for:
    /// - `leaseExpired` (per expired lease)
    /// - `leaseReshielded` (aggregated per reconciliation call)
    public mutating func reconcileExpiry(
        now: Date = Date(),
        record: ((UnlockLeaseLifecycleEvent) -> Void)? = nil
    ) -> [UUID] {
        let stillActive = leases.filter { $0.isActive(at: now) }
        let stillActiveIDs = Set(stillActive.map { $0.id })

        let newlyExpiredIDs = activeLeaseIDs.subtracting(stillActiveIDs)
        let newlyExpiredLeases = leases.filter { newlyExpiredIDs.contains($0.id) }
        let reshieldTargetIDs = Set(newlyExpiredLeases.map { $0.targetID })

        if !newlyExpiredLeases.isEmpty {
            // Emit one event per expired lease.
            for lease in newlyExpiredLeases {
                record?(UnlockLeaseLifecycleEvent(
                    type: .leaseExpired,
                    occurredAt: now,
                    requestID: lease.requestID,
                    leaseID: lease.id,
                    targetID: lease.targetID,
                    startAt: lease.startAt,
                    expiresAt: lease.expiresAt,
                    reason: lease.reason
                ))
            }

            record?(UnlockLeaseLifecycleEvent(
                type: .leaseReshielded,
                occurredAt: now,
                reshieldedTargetIDs: Array(reshieldTargetIDs),
                expiredLeaseIDs: newlyExpiredLeases.map { $0.id }
            ))
        }

        leases = stillActive
        activeLeaseIDs = stillActiveIDs

        return Array(reshieldTargetIDs)
    }
}
