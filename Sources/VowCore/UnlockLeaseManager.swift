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
    private var activeLeaseIDs: Set<UUID>

    /// Timestamp of the last reconciliation call.
    ///
    /// Used to make reconciliation idempotent under backwards/clock-skew by
    /// suppressing "newly expired" detection when `now` decreases.
    private var lastReconcileAt: Date?

    private enum CodingKeys: String, CodingKey {
        case leases
        case lastReconcileAt
    }

    public init(leases: [UnlockLease] = [], now: Date = Date()) {
        self.leases = leases
        self.activeLeaseIDs = Set(leases.filter { $0.isActive(at: now) }.map { $0.id })
        self.lastReconcileAt = now
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.leases = try container.decode([UnlockLease].self, forKey: .leases)
        self.lastReconcileAt = try container.decodeIfPresent(Date.self, forKey: .lastReconcileAt)

        let referenceDate = lastReconcileAt ?? Date()
        self.activeLeaseIDs = Set(leases.filter { $0.isActive(at: referenceDate) }.map { $0.id })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(leases, forKey: .leases)
        try container.encode(lastReconcileAt, forKey: .lastReconcileAt)
    }

    public static func == (lhs: UnlockLeaseManager, rhs: UnlockLeaseManager) -> Bool {
        lhs.leases == rhs.leases
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(leases)
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
    public mutating func grant(_ lease: UnlockLease, mergeActive: Bool = true, now: Date = Date()) -> UnlockLease {
        let (granted, _) = grantWithLifecycleEvents(lease, mergeActive: mergeActive, now: now)
        return granted
    }

    /// Grants a new lease and returns privacy-minimized lifecycle telemetry events.
    ///
    /// - When merging into an existing active lease: emits `leaseExtended`.
    /// - When appending as inactive-at-boundary/new: emits `leaseGranted`.
    public mutating func grantWithLifecycleEvents(
        _ lease: UnlockLease,
        mergeActive: Bool = true,
        now: Date = Date()
    ) -> (granted: UnlockLease, events: [UnlockLeaseLifecycleEvent]) {
        if mergeActive, let idx = leases.firstIndex(where: { $0.targetID == lease.targetID && $0.isActive(at: now) }) {
            let existing = leases[idx]
            let previousExpiresAt = existing.expiresAt
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

            return (
                merged,
                [
                    .leaseExtended(
                        .init(
                            leaseID: merged.id,
                            targetID: merged.targetID,
                            requestID: merged.requestID,
                            previousExpiresAt: previousExpiresAt,
                            newExpiresAt: extendedExpiresAt,
                            at: now
                        )
                    )
                ]
            )
        }

        leases.append(lease)
        return (
            lease,
            [
                .leaseGranted(
                    .init(
                        leaseID: lease.id,
                        targetID: lease.targetID,
                        requestID: lease.requestID,
                        startAt: lease.startAt,
                        expiresAt: lease.expiresAt,
                        at: now
                    )
                )
            ]
        )
    }

    /// Reconciles which leases are expired as of `now`.
    ///
    /// - Removes expired leases from `leases`.
    /// - Returns the targetIDs whose leases newly expired since the last
    ///   reconciliation, so callers can reshield those targets.
    public mutating func reconcileExpiry(now: Date = Date()) -> [UUID] {
        let (reshieldedTargetIDs, _) = reconcileExpiryWithLifecycleEvents(now: now)
        return reshieldedTargetIDs
    }

    /// Reconciles which leases are expired as of `now` and returns lifecycle telemetry.
    ///
    /// Backwards time (clock skew): reconciliation is idempotent; emit no events.
    public mutating func reconcileExpiryWithLifecycleEvents(
        now: Date = Date()
    ) -> (reshieldedTargetIDs: [UUID], events: [UnlockLeaseLifecycleEvent]) {
        // Backwards time (clock skew): keep state stable and emit nothing.
        if let last = lastReconcileAt, now < last {
            return ([], [])
        }

        let stillActive = leases.filter { $0.isActive(at: now) }
        let stillActiveIDs = Set(stillActive.map { $0.id })

        let newlyExpiredIDs = activeLeaseIDs.subtracting(stillActiveIDs)
        let expiredLeases = leases.filter { newlyExpiredIDs.contains($0.id) }
        let reshieldTargetIDsSet = Set(expiredLeases.map { $0.targetID })
        let reshieldTargetIDs = Array(reshieldTargetIDsSet).sorted { $0.uuidString < $1.uuidString }

        // Apply state updates.
        leases = stillActive
        activeLeaseIDs = stillActiveIDs
        lastReconcileAt = now

        guard !expiredLeases.isEmpty else {
            return ([], [])
        }

        var events: [UnlockLeaseLifecycleEvent] = []
        for lease in expiredLeases {
            events.append(
                .leaseExpired(
                    .init(
                        leaseID: lease.id,
                        targetID: lease.targetID,
                        requestID: lease.requestID,
                        startAt: lease.startAt,
                        expiresAt: lease.expiresAt,
                        at: now
                    )
                )
            )
        }

        // Exactly one reshield event per reconciliation call (aggregated).
        events.append(.leaseReshielded(.init(reshieldTargetIDs: reshieldTargetIDs, at: now)))

        return (reshieldTargetIDs, events)
    }
}
