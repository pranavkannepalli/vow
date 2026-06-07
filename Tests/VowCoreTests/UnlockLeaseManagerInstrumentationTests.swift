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

    func testGrantWithLifecycleEvents_emitsLeaseGranted() {
        let targetID = UUID()
        let t0 = Date(timeIntervalSince1970: 100)

        var mgr = UnlockLeaseManager()
        let lease = UnlockLease(
            targetID: targetID,
            startAt: t0,
            expiresAt: t0.addingTimeInterval(10),
            reason: "unit-test",
            requestID: UUID()
        )

        let result = mgr.grantWithLifecycleEvents(lease, now: t0)
        XCTAssertEqual(result.events.count, 1)

        guard case let .leaseGranted(payload) = result.events[0] else {
            return XCTFail("Expected leaseGranted event")
        }
        XCTAssertEqual(payload.leaseID, lease.id)
        XCTAssertEqual(payload.targetID, targetID)
        XCTAssertEqual(payload.requestID, lease.requestID)
        XCTAssertEqual(payload.startAt, lease.startAt)
        XCTAssertEqual(payload.expiresAt, lease.expiresAt)
        XCTAssertEqual(payload.at, t0)
    }

    func testGrantWithLifecycleEvents_emitsLeaseExtended_whenMergingActiveLease() {
        let targetID = UUID()
        let t0 = Date(timeIntervalSince1970: 200)

        let existing = UnlockLease(
            targetID: targetID,
            startAt: t0,
            expiresAt: t0.addingTimeInterval(10),
            reason: "old",
            requestID: UUID()
        )

        var mgr = UnlockLeaseManager(leases: [existing], now: t0)
        let extendDraft = UnlockLease(
            id: UUID(),
            targetID: targetID,
            startAt: t0.addingTimeInterval(1),
            expiresAt: t0.addingTimeInterval(25),
            reason: "new",
            requestID: UUID()
        )

        let result = mgr.grantWithLifecycleEvents(extendDraft, now: t0.addingTimeInterval(2))
        XCTAssertEqual(result.events.count, 1)

        guard case let .leaseExtended(payload) = result.events[0] else {
            return XCTFail("Expected leaseExtended event")
        }
        XCTAssertEqual(payload.leaseID, existing.id)
        XCTAssertEqual(payload.targetID, targetID)
        XCTAssertEqual(payload.previousExpiresAt, existing.expiresAt)
        XCTAssertEqual(payload.newExpiresAt, extendDraft.expiresAt)
        XCTAssertEqual(payload.at, t0.addingTimeInterval(2))

        XCTAssertEqual(result.granted.id, existing.id)
        XCTAssertEqual(result.granted.expiresAt, extendDraft.expiresAt)
    }

    func testReconcileExpiryWithLifecycleEvents_emitsLeaseExpired_andAggregatedReshielded() {
        let targetID = UUID()
        let t0 = Date(timeIntervalSince1970: 300)
        let lease = UnlockLease(
            targetID: targetID,
            startAt: t0,
            expiresAt: t0.addingTimeInterval(10),
            reason: "unit-test",
            requestID: UUID()
        )

        var mgr = UnlockLeaseManager(leases: [lease], now: t0)
        let result = mgr.reconcileExpiryWithLifecycleEvents(now: t0.addingTimeInterval(11))

        XCTAssertEqual(result.reshieldedTargetIDs, [targetID])
        XCTAssertEqual(result.events.count, 2)

        guard case let .leaseExpired(payload0) = result.events[0] else {
            return XCTFail("Expected leaseExpired event first")
        }
        XCTAssertEqual(payload0.leaseID, lease.id)
        XCTAssertEqual(payload0.targetID, targetID)
        XCTAssertEqual(payload0.at, t0.addingTimeInterval(11))

        guard case let .leaseReshielded(payload1) = result.events[1] else {
            return XCTFail("Expected leaseReshielded event last")
        }
        XCTAssertEqual(Set(payload1.reshieldTargetIDs), [targetID])
        XCTAssertEqual(payload1.at, t0.addingTimeInterval(11))
    }

    func testReconcileExpiryWithLifecycleEvents_clockSkew_backwards_emitsNothing() {
        let targetID = UUID()
        let t0 = Date(timeIntervalSince1970: 400)

        let lease = UnlockLease(
            targetID: targetID,
            startAt: t0.addingTimeInterval(5),
            expiresAt: t0.addingTimeInterval(15),
            reason: "skew",
            requestID: UUID()
        )

        var mgr = UnlockLeaseManager(leases: [lease], now: t0.addingTimeInterval(10))
        let forward = mgr.reconcileExpiryWithLifecycleEvents(now: t0.addingTimeInterval(10))
        XCTAssertEqual(forward.events.count, 0)

        let backwards = mgr.reconcileExpiryWithLifecycleEvents(now: t0.addingTimeInterval(4))
        XCTAssertEqual(backwards.events.count, 0)
    }

    func testReconcileExpiryWithLifecycleEvents_grantAtBoundary_isLeaseGranted_notExtended() {
        let targetID = UUID()
        let t0 = Date(timeIntervalSince1970: 500)
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

        let newDraft = UnlockLease(
            targetID: targetID,
            startAt: T,
            expiresAt: T.addingTimeInterval(20),
            reason: "new",
            requestID: UUID()
        )

        let grantResult = mgr.grantWithLifecycleEvents(newDraft, now: T)
        XCTAssertEqual(grantResult.events.count, 1)
        guard case let .leaseGranted(payload) = grantResult.events[0] else {
            return XCTFail("Expected leaseGranted at boundary")
        }
        XCTAssertEqual(payload.leaseID, grantResult.granted.id)
        XCTAssertNotEqual(grantResult.granted.id, oldLease.id)

        let reconcile = mgr.reconcileExpiryWithLifecycleEvents(now: T.addingTimeInterval(0.001))
        XCTAssertEqual(reconcile.events.filter({ if case .leaseExpired = $0 { return true } else { return false } }).count, 1)
    }

    func testReconcileExpiryWithLifecycleEvents_reshieldedEventIsAggregatedPerCall() {
        let t0 = Date(timeIntervalSince1970: 600)
        let target1 = UUID()
        let target2 = UUID()

        let lease1 = UnlockLease(
            targetID: target1,
            startAt: t0,
            expiresAt: t0.addingTimeInterval(10),
            reason: "l1",
            requestID: UUID()
        )
        let lease2 = UnlockLease(
            targetID: target2,
            startAt: t0,
            expiresAt: t0.addingTimeInterval(10),
            reason: "l2",
            requestID: UUID()
        )

        var mgr = UnlockLeaseManager(leases: [lease1, lease2], now: t0)
        let result = mgr.reconcileExpiryWithLifecycleEvents(now: t0.addingTimeInterval(11))

        XCTAssertEqual(result.reshieldedTargetIDs.count, 2)

        let reshieldEvents = result.events.filter { if case .leaseReshielded = $0 { return true } else { return false } }
        XCTAssertEqual(reshieldEvents.count, 1)

        guard case let .leaseReshielded(payload) = reshieldEvents[0] else {
            return XCTFail("Expected leaseReshielded payload")
        }
        XCTAssertEqual(Set(payload.reshieldTargetIDs), Set([target1, target2]))
    }
}
