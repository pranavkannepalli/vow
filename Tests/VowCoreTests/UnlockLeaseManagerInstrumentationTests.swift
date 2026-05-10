import XCTest
@testable import VowCore

final class UnlockLeaseManagerInstrumentationTests: XCTestCase {
    func testGrant_recordsLeaseGranted() {
        let now = Date(timeIntervalSince1970: 1000)
        let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        var manager = UnlockLeaseManager(leases: [], now: now)

        let lease = UnlockLease(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            targetID: targetID,
            startAt: now,
            expiresAt: now.addingTimeInterval(300),
            reason: "temp",
            requestID: requestID
        )

        var events: [UnlockLeaseLifecycleEvent] = []
        _ = manager.grant(lease, now: now, record: { events.append($0) })

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .leaseGranted)
        XCTAssertEqual(events[0].requestID, requestID)
        XCTAssertEqual(events[0].leaseID, lease.id)
        XCTAssertEqual(events[0].targetID, targetID)
        XCTAssertEqual(events[0].startAt, lease.startAt)
        XCTAssertEqual(events[0].expiresAt, lease.expiresAt)
        XCTAssertEqual(events[0].reason, lease.reason)
    }

    func testGrant_recordsLeaseExtended_whenMergeActive() {
        let now = Date(timeIntervalSince1970: 2000)
        let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let existingRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
        let newRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!

        let existingLease = UnlockLease(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
            targetID: targetID,
            startAt: now.addingTimeInterval(-10),
            expiresAt: now.addingTimeInterval(10),
            reason: "existing",
            requestID: existingRequestID
        )

        var manager = UnlockLeaseManager(leases: [existingLease], now: now)

        let newLease = UnlockLease(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
            targetID: targetID,
            startAt: now,
            expiresAt: now.addingTimeInterval(25),
            reason: "new",
            requestID: newRequestID
        )

        var events: [UnlockLeaseLifecycleEvent] = []
        let merged = manager.grant(newLease, now: now, record: { events.append($0) })

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .leaseExtended)
        XCTAssertEqual(merged.id, existingLease.id)
        XCTAssertEqual(merged.startAt, existingLease.startAt)
        XCTAssertEqual(merged.expiresAt, newLease.expiresAt)
        XCTAssertEqual(events[0].requestID, newRequestID)
        XCTAssertEqual(events[0].leaseID, existingLease.id)
        XCTAssertEqual(events[0].targetID, targetID)
        XCTAssertEqual(events[0].startAt, existingLease.startAt)
        XCTAssertEqual(events[0].expiresAt, newLease.expiresAt)
        XCTAssertEqual(events[0].reason, "new")
    }

    func testGrant_extendsActiveLease_whenExistingLeaseIsActive() {
        let now = Date(timeIntervalSince1970: 1000)
        let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let existingRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        let extendRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!

        let existingLease = UnlockLease(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            targetID: targetID,
            startAt: now.addingTimeInterval(-10),
            expiresAt: now.addingTimeInterval(10),
            reason: "existing",
            requestID: existingRequestID
        )

        var manager = UnlockLeaseManager(leases: [existingLease], now: now)

        let extendingLease = UnlockLease(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
            targetID: targetID,
            startAt: now,
            expiresAt: now.addingTimeInterval(20),
            reason: "extend",
            requestID: extendRequestID
        )

        var events: [UnlockLeaseLifecycleEvent] = []
        let merged = manager.grant(extendingLease, now: now, record: { events.append($0) })

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .leaseExtended)
        XCTAssertEqual(merged.id, existingLease.id)
        XCTAssertEqual(merged.startAt, existingLease.startAt)
        XCTAssertEqual(merged.expiresAt, extendingLease.expiresAt)
        XCTAssertEqual(events[0].leaseID, existingLease.id)
        XCTAssertEqual(events[0].requestID, extendRequestID)
        XCTAssertEqual(events[0].reason, "extend")
        XCTAssertEqual(manager.isTemporarilyUnlocked(targetID: targetID, at: now.addingTimeInterval(19)), true)
        XCTAssertEqual(manager.isTemporarilyUnlocked(targetID: targetID, at: now.addingTimeInterval(21)), false)
    }

    func testGrant_renewsLease_whenExistingLeaseExpiresAtBoundary() {
        let initialNow = Date(timeIntervalSince1970: 1000)
        let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        let existingRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
        let renewRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000023")!

        let existingLease = UnlockLease(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000024")!,
            targetID: targetID,
            startAt: initialNow.addingTimeInterval(-10),
            expiresAt: initialNow.addingTimeInterval(10), // active until exactly initialNow+10 (exclusive)
            reason: "existing",
            requestID: existingRequestID
        )

        var manager = UnlockLeaseManager(leases: [existingLease], now: initialNow)

        let renewNow = existingLease.expiresAt // boundary: date >= startAt && date < expiresAt
        let renewedLease = UnlockLease(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000025")!,
            targetID: targetID,
            startAt: renewNow,
            expiresAt: renewNow.addingTimeInterval(30),
            reason: "renew",
            requestID: renewRequestID
        )

        var events: [UnlockLeaseLifecycleEvent] = []
        let granted = manager.grant(renewedLease, now: renewNow, record: { events.append($0) })

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .leaseGranted)
        XCTAssertEqual(granted.id, renewedLease.id) // should not merge because existing is inactive at boundary
        XCTAssertEqual(granted.startAt, renewNow)
        XCTAssertEqual(granted.expiresAt, renewedLease.expiresAt)
        XCTAssertEqual(events[0].leaseID, renewedLease.id)
        XCTAssertEqual(events[0].requestID, renewRequestID)
        XCTAssertEqual(manager.isTemporarilyUnlocked(targetID: targetID, at: renewNow.addingTimeInterval(0.1)), true)
    }

    func testReconcileExpiry_expiresWithoutReunlock() {
        let lastReconcileAt = Date(timeIntervalSince1970: 1000)
        let reconcileNow = Date(timeIntervalSince1970: 1100)

        let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000032")!
        let leaseID = UUID(uuidString: "00000000-0000-0000-0000-000000000033")!

        let lease = UnlockLease(
            id: leaseID,
            targetID: targetID,
            startAt: lastReconcileAt.addingTimeInterval(-10),
            expiresAt: lastReconcileAt.addingTimeInterval(5), // expires before reconcileNow
            reason: "a",
            requestID: requestID
        )

        var manager = UnlockLeaseManager(leases: [lease], now: lastReconcileAt)

        var events: [UnlockLeaseLifecycleEvent] = []
        let reshielded = manager.reconcileExpiry(now: reconcileNow, record: { events.append($0) })

        XCTAssertEqual(reshielded, [targetID])
        XCTAssertEqual(events.filter { $0.type == .leaseExpired }.count, 1)
        XCTAssertEqual(events.filter { $0.type == .leaseReshielded }.count, 1)
        XCTAssertEqual(manager.isTemporarilyUnlocked(targetID: targetID, at: reconcileNow), false)

        var secondEvents: [UnlockLeaseLifecycleEvent] = []
        let reshieldedAgain = manager.reconcileExpiry(now: reconcileNow.addingTimeInterval(10), record: { secondEvents.append($0) })
        XCTAssertEqual(reshieldedAgain, [])
        XCTAssertEqual(secondEvents, [])
    }

    func testGrant_rapidRepeats_preservesLeaseID_andMaxExpiry() {
        let now = Date(timeIntervalSince1970: 1000)
        let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000041")!

        let lease1ID = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
        let request1ID = UUID(uuidString: "00000000-0000-0000-0000-000000000043")!

        let request2ID = UUID(uuidString: "00000000-0000-0000-0000-000000000044")!
        let request3ID = UUID(uuidString: "00000000-0000-0000-0000-000000000045")!

        var manager = UnlockLeaseManager(leases: [], now: now)

        let lease1 = UnlockLease(
            id: lease1ID,
            targetID: targetID,
            startAt: now,
            expiresAt: now.addingTimeInterval(30),
            reason: "r1",
            requestID: request1ID
        )

        var events: [UnlockLeaseLifecycleEvent] = []
        _ = manager.grant(lease1, now: now, record: { events.append($0) })

        // Repeat with a shorter lease; should not reduce max expiry.
        let lease2 = UnlockLease(
            id: UUID(),
            targetID: targetID,
            startAt: now.addingTimeInterval(2),
            expiresAt: now.addingTimeInterval(10),
            reason: "r2",
            requestID: request2ID
        )
        _ = manager.grant(lease2, now: now.addingTimeInterval(2), record: { events.append($0) })

        // Repeat with a longer lease; should extend to the later expiry.
        let lease3 = UnlockLease(
            id: UUID(),
            targetID: targetID,
            startAt: now.addingTimeInterval(5),
            expiresAt: now.addingTimeInterval(40),
            reason: "r3",
            requestID: request3ID
        )
        _ = manager.grant(lease3, now: now.addingTimeInterval(5), record: { events.append($0) })

        XCTAssertEqual(events.filter { $0.type == .leaseGranted }.count, 1)
        XCTAssertEqual(events.filter { $0.type == .leaseExtended }.count, 2)
        XCTAssertEqual(manager.leases.count, 1) // rapid repeats should merge into one stored lease
        XCTAssertEqual(manager.isTemporarilyUnlocked(targetID: targetID, at: now.addingTimeInterval(35)), true)
        XCTAssertEqual(manager.isTemporarilyUnlocked(targetID: targetID, at: now.addingTimeInterval(41)), false)
    }

    func testReconcileExpiry_clockSkew_backwards_doesNotReshieldAgain() {
        let lastReconcileAt = Date(timeIntervalSince1970: 1000)
        let nowForward = Date(timeIntervalSince1970: 2000)
        let nowBackwards = Date(timeIntervalSince1970: 1500)

        let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000051")!
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000052")!
        let leaseID = UUID(uuidString: "00000000-0000-0000-0000-000000000053")!

        let lease = UnlockLease(
            id: leaseID,
            targetID: targetID,
            startAt: lastReconcileAt.addingTimeInterval(-10),
            expiresAt: lastReconcileAt.addingTimeInterval(10),
            reason: "skew",
            requestID: requestID
        )

        var manager = UnlockLeaseManager(leases: [lease], now: lastReconcileAt)

        var events: [UnlockLeaseLifecycleEvent] = []
        let reshielded1 = manager.reconcileExpiry(now: nowForward, record: { events.append($0) })
        XCTAssertEqual(reshielded1, [targetID])
        XCTAssertEqual(events.filter { $0.type == .leaseExpired }.count, 1)
        XCTAssertEqual(events.filter { $0.type == .leaseReshielded }.count, 1)

        var secondEvents: [UnlockLeaseLifecycleEvent] = []
        let reshielded2 = manager.reconcileExpiry(now: nowBackwards, record: { secondEvents.append($0) })
        XCTAssertEqual(reshielded2, [])
        XCTAssertEqual(secondEvents, [])
    }

    func testGrant_doesNotExtendActiveLease_whenIncomingLeaseNotActiveAtNow() {
        let now = Date(timeIntervalSince1970: 1000)
        let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000061")!

        let existingRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000062")!
        let incomingRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000063")!

        let existingLease = UnlockLease(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000064")!,
            targetID: targetID,
            startAt: now.addingTimeInterval(-10),
            expiresAt: now.addingTimeInterval(10),
            reason: "existing",
            requestID: existingRequestID
        )

        var manager = UnlockLeaseManager(leases: [existingLease], now: now)

        // Incoming lease is scheduled to start after the existing lease expires.
        // If we merged it incorrectly, it would extend the existing unlock window.
        let incomingLease = UnlockLease(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000065")!,
            targetID: targetID,
            startAt: now.addingTimeInterval(20),
            expiresAt: now.addingTimeInterval(40),
            reason: "incoming_future_start",
            requestID: incomingRequestID
        )

        var events: [UnlockLeaseLifecycleEvent] = []
        let granted = manager.grant(incomingLease, now: now, record: { events.append($0) })

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .leaseGranted)
        XCTAssertEqual(granted.id, incomingLease.id)
        XCTAssertEqual(manager.leases.count, 2)

        let storedExisting = manager.leases.first { $0.id == existingLease.id }!
        XCTAssertEqual(storedExisting.expiresAt, existingLease.expiresAt) // should not be extended

        XCTAssertEqual(manager.isTemporarilyUnlocked(targetID: targetID, at: now.addingTimeInterval(15)), false)
        XCTAssertEqual(manager.isTemporarilyUnlocked(targetID: targetID, at: now.addingTimeInterval(25)), true)
    }

    func testReconcileExpiry_recordsLeaseExpiredAndReshielded() {
        let lastReconcileAt = Date(timeIntervalSince1970: 3000)
        let reconcileNow = Date(timeIntervalSince1970: 3050)

        let targetA = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!
        let targetB = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!

        let requestA = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
        let requestB = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!

        let lease1 = UnlockLease(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000D")!,
            targetID: targetA,
            startAt: lastReconcileAt.addingTimeInterval(-10),
            expiresAt: lastReconcileAt.addingTimeInterval(5),
            reason: "a",
            requestID: requestA
        )

        let lease2 = UnlockLease(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000E")!,
            targetID: targetB,
            startAt: lastReconcileAt.addingTimeInterval(-20),
            expiresAt: lastReconcileAt.addingTimeInterval(1),
            reason: "b",
            requestID: requestB
        )

        var manager = UnlockLeaseManager(leases: [lease1, lease2], now: lastReconcileAt)

        var events: [UnlockLeaseLifecycleEvent] = []
        let reshielded = manager.reconcileExpiry(now: reconcileNow, record: { events.append($0) })

        XCTAssertEqual(Set(reshielded), Set([targetA, targetB]))

        // 2 expired events + 1 reshielded event
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.filter { $0.type == .leaseExpired }.count, 2)
        XCTAssertEqual(events.filter { $0.type == .leaseReshielded }.count, 1)

        let expiredIDs = Set(events.compactMap { evt -> UUID? in
            if evt.type == .leaseExpired { return evt.leaseID } else { return nil }
        })
        XCTAssertEqual(expiredIDs, Set([lease1.id, lease2.id]))

        let reshieldEvent = events.first { $0.type == .leaseReshielded }!
        XCTAssertEqual(Set(reshieldEvent.reshieldedTargetIDs ?? []), Set([targetA, targetB]))
        XCTAssertEqual(Set(reshieldEvent.expiredLeaseIDs ?? []), Set([lease1.id, lease2.id]))
    }
}
