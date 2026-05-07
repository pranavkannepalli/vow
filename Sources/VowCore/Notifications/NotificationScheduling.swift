import Foundation

public protocol NotificationScheduling {
    func scheduleNotification(_ request: NotificationRequest) async throws
    func cancelNotifications(identifiers: [String]) async throws
}

/// Default scheduler for tests/host environments without OS notifications.
public struct NoopNotificationScheduler: NotificationScheduling {
    public init() {}

    public func scheduleNotification(_ request: NotificationRequest) async throws {
        _ = request
    }

    public func cancelNotifications(identifiers: [String]) async throws {
        _ = identifiers
    }
}

#if canImport(UserNotifications)
import UserNotifications

/// iOS scheduler implementation using `UNUserNotificationCenter`.
public struct UserNotificationsScheduler: NotificationScheduling {
    public let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func scheduleNotification(_ request: NotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.content.title
        content.body = request.content.body
        content.sound = .default

        let triggerDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: request.scheduledAt
        )

        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDateComponents, repeats: false)
        let un = UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger)

        center.add(un)
    }

    public func cancelNotifications(identifiers: [String]) async throws {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
#endif
