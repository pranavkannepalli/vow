import XCTest
@testable import VowCore

final class VowCoreSpecV2QATests: XCTestCase {
    func testStateMachine_happyPath_noEvidence() {
        var sm = UnlockRequestStateMachine(evidenceRequired: false)
        XCTAssertEqual(sm.state, .requestCreated)

        sm.apply(.frictionTimerStarted)
        XCTAssertEqual(sm.state, .frictionWaiting)

        sm.apply(.evidenceRequired)
        XCTAssertEqual(sm.state, .evidenceCompleted)

        sm.apply(.aiReviewed)
        XCTAssertEqual(sm.state, .aiReviewed)

        sm.apply(.decisionApproved)
        XCTAssertEqual(sm.state, .decisionApprovedTempUnlock)

        // v1 state machine treats sessionObserved as a no-op for state.
        sm.apply(.sessionObserved)
        XCTAssertEqual(sm.state, .decisionApprovedTempUnlock)

        sm.apply(.sessionClosed)
        XCTAssertEqual(sm.state, .sessionClosed)

        sm.apply(.reviewLogged)
        XCTAssertEqual(sm.state, .reviewLogged)
        XCTAssertTrue(sm.state.isTerminal)
    }

    func testStateMachine_transitions_evidenceRequired() {
        var sm = UnlockRequestStateMachine(evidenceRequired: true)

        sm.apply(.frictionTimerStarted)
        XCTAssertEqual(sm.state, .frictionWaiting)

        sm.apply(.evidenceRequired)
        XCTAssertEqual(sm.state, .evidencePending)

        sm.apply(.evidenceCompleted)
        XCTAssertEqual(sm.state, .evidenceCompleted)

        sm.apply(.aiReviewed)
        XCTAssertEqual(sm.state, .aiReviewed)

        sm.apply(.decisionDeferred)
        XCTAssertEqual(sm.state, .decisionDeferred)
        XCTAssertTrue(sm.state.isTerminal)
    }

    func testStateMachine_ignoresInvalidTransitions() {
        var sm = UnlockRequestStateMachine(evidenceRequired: false)

        // decisionApproved is invalid before aiReviewed
        sm.apply(.decisionApproved)
        XCTAssertEqual(sm.state, .requestCreated)
    }

    func testEvidenceTaskCompletionLogic() {
        let completedAt = Date(timeIntervalSince1970: 1000)

        XCTAssertTrue(EvidenceTaskCompletionLogic.isCompleted(completedAt: completedAt, at: completedAt))
        XCTAssertTrue(EvidenceTaskCompletionLogic.isCompleted(completedAt: completedAt, at: completedAt.addingTimeInterval(1)))
        XCTAssertFalse(EvidenceTaskCompletionLogic.isCompleted(completedAt: completedAt, at: completedAt.addingTimeInterval(-1)))
    }

    func testFrictionEngine_seconds_returnsPolicyLowerBounds() {
        let engine = FrictionEngine(policy: FrictionPolicy(lowSeconds: 10...30, mediumSeconds: 60...120, highSeconds: 180...300))

        XCTAssertEqual(engine.seconds(for: FrictionInputs(tier: .low)), 10)
        XCTAssertEqual(engine.seconds(for: FrictionInputs(tier: .medium)), 60)
        XCTAssertEqual(engine.seconds(for: FrictionInputs(tier: .high)), 180)
    }

    func testFrictionEngine_performance_constantTime() {
        let engine = FrictionEngine()
        let inputs = FrictionInputs(tier: .high)

        measure {
            _ = engine.seconds(for: inputs)
        }
    }
}

private extension EvidenceTaskCompletionLogic {
    static func isCompleted(completedAt: Date?, at date: Date) -> Bool {
        EvidenceTaskCompletionLogic.isCompleted(completedAt, at: date)
    }
}
