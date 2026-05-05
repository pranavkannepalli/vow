import Foundation

public struct NotificationRequest: Codable, Hashable, Equatable, Identifiable {
    public var id: String { identifier }

    public var identifier: String
    public var kind: NotificationKind
    public var scheduledAt: Date
    public var content: NotificationContent

    public init(
        identifier: String,
        kind: NotificationKind,
        scheduledAt: Date,
        content: NotificationContent
    ) {
        self.identifier = identifier
        self.kind = kind
        self.scheduledAt = scheduledAt
        self.content = content
    }
}
