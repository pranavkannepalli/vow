import XCTest
@testable import VowCore

final class UnlockLeaseManagerInstrumentationTests: XCTestCase {
    func testReconcileExpiry_expiresWithoutReunlock() {
        let targetID = UUID()
        let leaseStart = Date(timeIntervalSince1970: 0)
        let leaseExpiresAt = leaseStart.addingTimeInterval(10)

        var mgr = UnlockLeaseManager(
            leases: [UnlockLease(
                targetID: targetID,
                startAt: leaseStart,
                expiresAt: leaseExpiresAt,
                reason: "unit-test",
                requestID: UUID()
            )],
            now: leaseStart
        )

        XCTAssertTrue(mgr.isTemporarilyUnlocked(targetID: targetID, at: leaseStart.addingTimeInterval(1)))

        let reshielded = mgr.reconcileExpiry(now: leaseStart.addingTimeInterval(11))
        XCTAssertEqual(Set(reshielded), [targetID])
        XCTAssertFalse(mgr.isTemporarilyUnlocked(targetID: targetID, at: leaseStart.addingTimeInterval(11)))
    }

    func testGrant_renewsLease_whenExistingLeaseExpiresAtBoundary() {
        let targetID = UUID()
        let t0 = Date(timeIntervalSince1970: 100)
        let T = t0.addingTimeInterval(10)

        let oldLease = UnlockLease(
            targetID: targetID,
            startAt: t0,
            expiresAt: T,
            reason: "old",
            requestID: UUID()
        )

        var mgr = UnlockLeaseManager(leases: [oldLease], now: t0)
        XCTAssertTrue(mgr.isTemporarilyUnlocked(targetID: targetID, at: T.addingTimeInterval(-1)))

        let newLeaseDraft = UnlockLease(
            targetID: targetID,
            startAt: T,
            expiresAt: T.addingTimeInterval(20),
            reason: "new",
            requestID: UUID()
        )
        let grantedNewLease = mgr.grant(newLeaseDraft, now: T)

        // At boundary, the old lease is inactive but still present until reconciliation.
        XCTAssertEqual(mgr.leases.count, 2)
        XCTAssertNotEqual(grantedNewLease.id, oldLease.id)

        let reshielded = mgr.reconcileExpiry(now: T.addingTimeInterval(0.001))
        XCTAssertEqual(Set(reshielded), [targetID])

        // Old lease should be removed; newly granted lease stays active.
        XCTAssertEqual(mgr.leases.count, 1)
        XCTAssertEqual(mgr.leases[0].id, grantedNewLease.id)
        XCTAssertEqual(mgr.leases[0].expiresAt, newLeaseDraft.expiresAt)
    }

    func testGrant_rapidRepeats_preservesLeaseID_andMaxExpiry() {
        let targetID = UUID()
        let t0 = Date(timeIntervalSince1970: 200)

        var mgr = UnlockLeaseManager()

        let lease1 = UnlockLease(
            targetID: targetID,
            startAt: t0,
            expiresAt: t0.addingTimeInterval(5),
            reason: "l1",
            requestID: UUID()
        )
        let granted1 = mgr.grant(lease1, now: t0)

        let lease2 = UnlockLease(
            targetID: targetID,
            startAt: t0.addingTimeInterval(2),
            expiresAt: t0.addingTimeInterval(8),
            reason: "l2",
            requestID: UUID()
        )
        let granted2 = mgr.grant(lease2, now: t0.addingTimeInterval(2))

        XCTAssertEqual(mgr.leases.count, 1)
        XCTAssertEqual(granted2.id, granted1.id)
        XCTAssertEqual(mgr.leases[0].startAt, granted1.startAt)
        XCTAssertEqual(mgr.leases[0].expiresAt, t0.addingTimeInterval(8))

        let reshielded1 = mgr.reconcileExpiry(now: t0.addingTimeInterval(9))
        XCTAssertEqual(Set(reshielded1), [targetID])

        // Consecutive reconciliation should emit nothing.
        let reshielded2 = mgr.reconcileExpiry(now: t0.addingTimeInterval(10))
        XCTAssertTrue(reshielded2.isEmpty)
    }

    func testReconcileExpiry_clockSkew_backwards_doesNotReshieldAgain() {
        let targetID = UUID()
        let t0 = Date(timeIntervalSince1970: 300)

        let lease = UnlockLease(
            targetID: targetID,
            startAt: t0.addingTimeInterval(5),
            expiresAt: t0.addingTimeInterval(15),
            reason: "skew",
            requestID: UUID()
        )

        // Initialize with nowForward (lease is active at 10s, but not active at 4s).
        var mgr = UnlockLeaseManager(leases: [lease], now: t0.addingTimeInterval(10))
        XCTAssertTrue(mgr.isTemporarilyUnlocked(targetID: targetID, at: t0.addingTimeInterval(10)))

        _ = mgr.reconcileExpiry(now: t0.addingTimeInterval(10))
        XCTAssertEqual(mgr.leases.count, 1)

        // Backwards reconciliation: should be idempotent and emit nothing.
        let reshieldedBackwards = mgr.reconcileExpiry(now: t0.addingTimeInterval(4))
        XCTAssertTrue(reshieldedBackwards.isEmpty)

        // Lease state should remain stable.
        XCTAssertEqual(mgr.leases.count, 1)
        XCTAssertEqual(mgr.leases[0].id, lease.id)
    }
}
