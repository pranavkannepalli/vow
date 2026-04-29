import Foundation

public enum EvidenceTaskType: String, Codable {
    case steps
    case focusTimer
    case journal
}

public protocol EvidenceTask: Codable {
    var id: UUID { get }
    var type: EvidenceTaskType { get }
    var createdAt: Date { get }
    var completedAt: Date? { get set }

    /// v1: used by the app to gate transitions.
    func isCompleted(at date: Date) -> Bool

    /// TODO: implement concrete tasks with HealthKit / journal completion signals.
}

public struct EvidenceTaskCompletion: Codable, Hashable {
    public var taskID: UUID
    public var completedAt: Date
}

public protocol EvidenceTaskRunner {
    associatedtype Task: EvidenceTask

    func start(_ task: Task) async throws
    func checkCompletion(_ task: Task, at date: Date) async -> Bool
}
