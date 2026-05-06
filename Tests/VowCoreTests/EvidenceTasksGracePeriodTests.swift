import XCTest
@testable import VowCore

final class EvidenceTasksGracePeriodTests: XCTestCase {
    func test_stepsEvidenceTask_completionCountsWithinGraceWindow() {
        let calendar = Calendar.current
        let grace: TimeInterval = 2 * 60 * 60

        let today = calendar.startOfDay(for: Date())
        let unlockRequestedAt = today.addingTimeInterval(23 * 60 * 60)

        let task = StepsEvidenceTask(
            unlockRequestedAt: unlockRequestedAt,
            targetStepsDelta: 1200,
            dailyGracePeriodSeconds: grace
        )

        // Next local day, 1 hour into it (within grace).
        let nextDay = calendar.date(byAdding: .day, value: 1, to: today)!
        let completedWithinGrace = nextDay.addingTimeInterval(1 * 60 * 60)

        var completedTask = task
        completedTask.completedAt = completedWithinGrace
        XCTAssertTrue(completedTask.isCompleted(at: completedWithinGrace))
    }

    func test_stepsEvidenceTask_completionBeyondGraceWindowDoesNotCount() {
        let calendar = Calendar.current
        let grace: TimeInterval = 2 * 60 * 60

        let today = calendar.startOfDay(for: Date())
        let unlockRequestedAt = today.addingTimeInterval(23 * 60 * 60)

        let task = StepsEvidenceTask(
            unlockRequestedAt: unlockRequestedAt,
            targetStepsDelta: 1200,
            dailyGracePeriodSeconds: grace
        )

        // Next local day, 3 hours into it (missed).
        let nextDay = calendar.date(byAdding: .day, value: 1, to: today)!
        let completedMissed = nextDay.addingTimeInterval(3 * 60 * 60)

        var completedTask = task
        completedTask.completedAt = completedMissed
        XCTAssertFalse(completedTask.isCompleted(at: completedMissed))
    }
}
