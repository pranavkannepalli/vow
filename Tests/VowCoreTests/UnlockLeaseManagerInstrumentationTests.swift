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
