import XCTest
@testable import VowCore

final class NfcRuntimeEnforcerTests: XCTestCase {
    final class CapturingScheduler: AlarmScheduling {
        var scheduled: [(targetID: UUID, requestID: UUID, violation: NfcViolation)] = []

        func scheduleEnforcementAlarm(
            targetID: UUID,
            requestID: UUID,
            violation: NfcViolation,
            now: Date,
            gracePeriodSeconds: TimeInterval
        ) async throws {
            scheduled.append((targetID: targetID, requestID: requestID, violation: violation))
        }
    }

    func testVerify_returnsVerified_whenVerifierIsTrue() async {
        let scheduler = CapturingScheduler()
        let enforcer = NfcRuntimeEnforcer(
            targetID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            verifier: { true },
            scheduler: scheduler,
            gracePeriodSeconds: 0,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = await enforcer.verify(
            requestID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        )

        switch result {
        case .verified:
            break
        case .notVerified:
            XCTFail("Expected verified")
        }

        XCTAssertEqual(scheduler.scheduled.count, 0)
    }

    func testVerify_schedulesAlarmAndDenies_whenVerifierIsFalse() async {
        let scheduler = CapturingScheduler()
        let targetID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let requestID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        let enforcer = NfcRuntimeEnforcer(
            targetID: targetID,
            verifier: { false },
            scheduler: scheduler,
            gracePeriodSeconds: 0,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = await enforcer.verify(requestID: requestID)

        switch result {
        case .verified:
            XCTFail("Expected notVerified")
        case .notVerified(let violation):
            XCTAssertEqual(violation, .notVerified)
        }

        XCTAssertEqual(scheduler.scheduled.count, 1)
        XCTAssertEqual(scheduler.scheduled[0].targetID, targetID)
        XCTAssertEqual(scheduler.scheduled[0].requestID, requestID)
        XCTAssertEqual(scheduler.scheduled[0].violation, .notVerified)
    }

    func testVerify_schedulesAlarmAndDenies_whenVerifierThrows() async {
        enum ReaderError: Error { case boom }

        let scheduler = CapturingScheduler()
        let targetID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let requestID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        let enforcer = NfcRuntimeEnforcer(
            targetID: targetID,
            verifier: { throw ReaderError.boom },
            scheduler: scheduler,
            gracePeriodSeconds: 0,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = await enforcer.verify(requestID: requestID)

        switch result {
        case .verified:
            XCTFail("Expected notVerified")
        case .notVerified(let violation):
            XCTAssertEqual(violation, .notVerified)
        }

        XCTAssertEqual(scheduler.scheduled.count, 1)
        XCTAssertEqual(scheduler.scheduled[0].targetID, targetID)
        XCTAssertEqual(scheduler.scheduled[0].requestID, requestID)
        XCTAssertEqual(scheduler.scheduled[0].violation, .notVerified)
    }
}
