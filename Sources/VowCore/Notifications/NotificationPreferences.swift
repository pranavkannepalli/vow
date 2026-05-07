import Foundation

public enum NotificationKind: String, Codable, Hashable {
    case habitReminders
    case dailyCheckInPrompt
    case focusSessionStartNudge
}

/// User-configurable opt-in controls + reminder timing defaults.
///
/// Host app should persist this (e.g., in App Group storage) and feed it
/// back into `NotificationComposer`.
public struct NotificationPreferences: Codable, Hashable, Equatable {
    public var habitRemindersEnabled: Bool
    public var dailyCheckInEnabled: Bool
    public var focusSessionStartNudgeEnabled: Bool

    /// Default daily time for habit reminder nudges.
    public var habitReminderHour: Int
    public var habitReminderMinute: Int

    /// Default daily time for the life check-in prompt.
    public var dailyCheckInHour: Int
    public var dailyCheckInMinute: Int

    /// Default daily time for prompting a focus sprint when the user is idle.
    public var focusSessionStartNudgeHour: Int
    public var focusSessionStartNudgeMinute: Int

    public init(
        habitRemindersEnabled: Bool = true,
        dailyCheckInEnabled: Bool = true,
        focusSessionStartNudgeEnabled: Bool = true,
        habitReminderHour: Int = 9,
        habitReminderMinute: Int = 0,
        dailyCheckInHour: Int = 20,
        dailyCheckInMinute: Int = 0,
        focusSessionStartNudgeHour: Int = 11,
        focusSessionStartNudgeMinute: Int = 30
    ) {
        self.habitRemindersEnabled = habitRemindersEnabled
        self.dailyCheckInEnabled = dailyCheckInEnabled
        self.focusSessionStartNudgeEnabled = focusSessionStartNudgeEnabled
        self.habitReminderHour = habitReminderHour
        self.habitReminderMinute = habitReminderMinute
        self.dailyCheckInHour = dailyCheckInHour
        self.dailyCheckInMinute = dailyCheckInMinute
        self.focusSessionStartNudgeHour = focusSessionStartNudgeHour
        self.focusSessionStartNudgeMinute = focusSessionStartNudgeMinute
    }
}
