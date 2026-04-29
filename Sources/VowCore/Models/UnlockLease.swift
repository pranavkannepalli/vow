import Foundation

public struct UnlockLease: Codable, Hashable, Identifiable {
    public let id: UUID
    public let targetID: UUID
    public let startAt: Date
    public let expiresAt: Date
    public let reason: String
    public let requestID: UUID

    public init(
        id: UUID = UUID(),
        targetID: UUID,
        startAt: Date,
        expiresAt: Date,
        reason: String,
        requestID: UUID
    ) {
        self.id = id
        self.targetID = targetID
        self.startAt = startAt
        self.expiresAt = expiresAt
        self.reason = reason
        self.requestID = requestID
    }

    public func isActive(at date: Date = Date()) -> Bool {
        date >= startAt && date < expiresAt
    }
}
