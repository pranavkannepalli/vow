import XCTest
@testable import VowCore

final class NfcRuntimeEnforcerTests: XCTestCase {
    private struct MockAlarmScheduler: AlarmScheduling {
        struct Call: Equatable {
            let at: Date
            let payload: AlarmPayload
        }

        var calls: [Call] = []

        mutating func scheduleCall(at: Date, payload: AlarmPayload) {
            calls.append(.init(at: at, payload: payload))
        }

        func scheduleAlarm(at date: Date, payload: AlarmPayload) async throws {
            // Note: this is intentionally not actor-isolated; the test uses
            // deterministic single-threaded execution.
            // (We can’t mutate `self` from a `func` without `var` storage being
            // captured, so we rely on class box below.)
            fatalError("Use MockAlarmSchedulerBox")
        }
    }

    private final class MockAlarmSchedulerBox: AlarmScheduling {
        var calls: [MockAlarmScheduler.Call] = []

        func scheduleAlarm(at date: Date, payload: AlarmPayload) async throws {
            calls.append(.init(at: date, payload: payload))
        }
    }

    func testNfcRuntimeEnforcer_notVerified_schedulesAlarmAndReturnsViolation() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let grace: TimeInterval = 10

        let scheduler = MockAlarmSchedulerBox()
        let verifier: @Sendable () async throws -> Bool = { false }

        let enforcer = NfcRuntimeEnforcer(
            verifier: verifier,
            scheduler: scheduler,
            gracePeriodSeconds: grace,
            now: { fixedNow }
        )

        let outcome = try await enforcer.verify(targetID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, requestID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, at: fixedNow)

        switch outcome {
        case .verified:
            XCTFail("Expected notVerified")

        case .notVerified(let violation):
            XCTAssertEqual(violation.detectedAt, fixedNow)
            XCTAssertEqual(violation.graceEndsAt, fixedNow.addingTimeInterval(grace))
            XCTAssertEqual(violation.alarmAt, violation.graceEndsAt)

            XCTAssertEqual(scheduler.calls.count, 1)
            XCTAssertEqual(scheduler.calls[0].at, violation.alarmAt)
            XCTAssertEqual(scheduler.calls[0].payload.violation, violation)
        }
    }

    func testNfcRuntimeEnforcer_verified_doesNotScheduleAlarm() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let grace: TimeInterval = 10

        let scheduler = MockAlarmSchedulerBox()
        let verifier: @Sendable () async throws -> Bool = { true }

        let enforcer = NfcRuntimeEnforcer(
            verifier: verifier,
            scheduler: scheduler,
            gracePeriodSeconds: grace,
            now: { fixedNow }
        )

        let outcome = try await enforcer.verify(targetID: UUID(), requestID: UUID(), at: fixedNow)

        XCTAssertEqual(outcome, .verified)
        XCTAssertTrue(scheduler.calls.isEmpty)
    }
}
