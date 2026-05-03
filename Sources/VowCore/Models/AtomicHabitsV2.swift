import Foundation

public enum AtomicHabitKind: String, Codable, Hashable {
    case generic
    case focusSessionsCompleted
    case journalCompleted
    case stepsCompleted
}

public enum AtomicHabitCompletionStatus: String, Codable, Hashable {
    case notStarted
    case inProgress
    case completed
}

public struct AtomicHabitDefinitionRecord: Codable, Hashable, Identifiable {
    public var id: UUID
    public var userID: UUID
    public var name: String
    public var habitKind: AtomicHabitKind
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        userID: UUID,
        name: String,
        habitKind: AtomicHabitKind = .generic,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.name = name
        self.habitKind = habitKind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct AtomicHabitInstanceRecord: Codable, Hashable, Identifiable {
    public var id: UUID
    public var userID: UUID
    public var habitDefinitionID: UUID
    public var date: Date

    public var status: AtomicHabitCompletionStatus
    public var completedAt: Date?
    public var occurrenceCount: Int

    /// Audit/debug: evidence inputs that contributed to completion.
    public var evidence: [String: String]

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        userID: UUID,
        habitDefinitionID: UUID,
        date: Date,
        status: AtomicHabitCompletionStatus = .notStarted,
        completedAt: Date? = nil,
        occurrenceCount: Int = 0,
        evidence: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.habitDefinitionID = habitDefinitionID
        self.date = date
        self.status = status
        self.completedAt = completedAt
        self.occurrenceCount = occurrenceCount
        self.evidence = evidence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
