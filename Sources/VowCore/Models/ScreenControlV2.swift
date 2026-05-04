import Foundation

public enum ScreenControlEventType: String, Codable, Hashable {
    // App/extension lifecycle & shields
    case blockedAttempt
    case shieldShown
    case unlockRequested
    case unlockGranted
    case unlockDenied
    case unlockDeferred

    // Evidence / session observation
    case focusSessionStarted
    case focusSessionCompleted
    case focusSessionInterrupted

    // Generic fallback
    case other
}

public struct FocusSessionRecord: Codable, Hashable, Identifiable {
    public var id: UUID
    public var userID: UUID
    public var requestID: UUID?

    public var startedAt: Date
    public var endedAt: Date?

    public var targetSeconds: Int
    public var actualSeconds: Int?

    public var allowsPause: Bool
    public var interrupted: Bool

    public var metadata: [String: String]

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        userID: UUID,
        requestID: UUID? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        targetSeconds: Int,
        actualSeconds: Int? = nil,
        allowsPause: Bool = false,
        interrupted: Bool = false,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.requestID = requestID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.targetSeconds = targetSeconds
        self.actualSeconds = actualSeconds
        self.allowsPause = allowsPause
        self.interrupted = interrupted
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ScreenControlEventRecord: Codable, Hashable, Identifiable {
    public var id: UUID
    public var userID: UUID

    public var occurredAt: Date
    public var eventType: ScreenControlEventType

    public var requestID: UUID?

    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        userID: UUID,
        occurredAt: Date = Date(),
        eventType: ScreenControlEventType,
        requestID: UUID? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.userID = userID
        self.occurredAt = occurredAt
        self.eventType = eventType
        self.requestID = requestID
        self.metadata = metadata
    }
}
