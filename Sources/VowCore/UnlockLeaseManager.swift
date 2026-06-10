import Foundation

/// Manages temporary unlock leases and determines which targets need to be
/// "reshielded" once leases expire.
///
/// This is intentionally UI/ScreenTime-agnostic: the caller can translate
/// returned targetIDs into ManagedSettings shield updates.
public struct UnlockLeaseManager: Codable, Hashable {
    public var leases: [UnlockLease]

    /// Optional hook for privacy-minimized lease lifecycle telemetry.
    ///
    /// Not encoded/decoded (telemetry is runtime-only).
    private var leaseLifecycleRecorder: (@Sendable (UnlockLeaseLifecycleEvent) -> Void)?

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

    public init(
        leases: [UnlockLease] = [],
        now: Date = Date(),
        leaseLifecycleRecorder: (@Sendable (UnlockLeaseLifecycleEvent) -> Void)? = nil
    ) {
        self.leases = leases
        self.leaseLifecycleRecorder = leaseLifecycleRecorder
        self.activeLeaseIDs = Set(leases.filter { $0.isActive(at: now) }.map { $0.id })
        self.lastReconcileAt = now
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.leases = try container.decode([UnlockLease].self, forKey: .leases)
        self.lastReconcileAt = try container.decodeIfPresent(Date.self, forKey: .lastReconcileAt)

        let referenceDate = lastReconcileAt ?? Date()
        self.activeLeaseIDs = Set(leases.filter { $0.isActive(at: referenceDate) }.map { $0.id })

        self.leaseLifecycleRecorder = nil
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
        if mergeActive, let idx = leases.firstIndex(where: { $0.targetID == lease.targetID && $0.isActive(at: now) }) {
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

            leaseLifecycleRecorder?(
                .leaseExtended(
                    .init(
                        leaseID: merged.id,
                        targetID: merged.targetID,
                        requestID: merged.requestID,
                        previousExpiresAt: existing.expiresAt,
                        newExpiresAt: merged.expiresAt,
                        at: now
                    )
                )
            )

            if merged.isActive(at: now) {
                activeLeaseIDs.insert(merged.id)
            }

            return merged
        }

        leases.append(lease)

        leaseLifecycleRecorder?(
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
        )

        if lease.isActive(at: now) {
            activeLeaseIDs.insert(lease.id)
        }

        return lease
    }

    /// Reconciles which leases are expired as of `now`.
    ///
    /// - Removes expired leases from `leases`.
    /// - Returns the targetIDs whose leases newly expired since the last
    ///   reconciliation, so callers can reshield those targets.
    public mutating func reconcileExpiry(now: Date = Date()) -> [UUID] {
        // Backwards time (clock skew): keep state stable and emit nothing.
        if let last = lastReconcileAt, now < last {
            return []
        }

        let stillActive = leases.filter { $0.isActive(at: now) }
        let stillActiveIDs = Set(stillActive.map { $0.id })

        let newlyExpiredIDs = activeLeaseIDs.subtracting(stillActiveIDs)
        let newlyExpiredLeases = leases.filter { newlyExpiredIDs.contains($0.id) }

        let reshieldTargetIDsSet = Set(newlyExpiredLeases.map { $0.targetID })
        let reshieldTargetIDs = reshieldTargetIDsSet
            .sorted { $0.uuidString < $1.uuidString }

        leases = stillActive
        activeLeaseIDs = stillActiveIDs
        lastReconcileAt = now

        if let recorder = leaseLifecycleRecorder, !newlyExpiredLeases.isEmpty {
            let expiredLeasesOrdered = newlyExpiredLeases
                .sorted {
                    $0.expiresAt < $1.expiresAt ||
                    ($0.expiresAt == $1.expiresAt && $0.id.uuidString < $1.id.uuidString)
                }

            for expired in expiredLeasesOrdered {
                recorder(
                    .leaseExpired(
                        .init(
                            leaseID: expired.id,
                            targetID: expired.targetID,
                            requestID: expired.requestID,
                            startAt: expired.startAt,
                            expiresAt: expired.expiresAt,
                            at: now
                        )
                    )
                )
            }

            recorder(
                .leaseReshielded(
                    .init(
                        reshieldTargetIDs: reshieldTargetIDs,
                        at: now
                    )
                )
            )
        }

        return reshieldTargetIDs
    }
}
