import Foundation

protocol TaskNotificationManaging: Sendable {
    func sendFocusReminder(taskTitle: String)
    func scheduleEstimateReached(taskID: UUID, taskTitle: String, after seconds: Int)
    func cancelEstimateReminder(taskID: UUID)
}

protocol WorktimeNotificationManaging: Sendable {
    func scheduleWorktimeTarget(
        workDate: Date,
        startAt: Date,
        expectedEndAt: Date,
        targetMinutes: Int
    )
    func cancelWorktimeTarget(workDate: Date)
}

final class NotificationManager: TaskNotificationManaging, WorktimeNotificationManaging, @unchecked Sendable {
    static let shared = NotificationManager()
    func sendFocusReminder(taskTitle: String) {}
    func scheduleEstimateReached(taskID: UUID, taskTitle: String, after seconds: Int) {}
    func cancelEstimateReminder(taskID: UUID) {}
    func scheduleWorktimeTarget(workDate: Date, startAt: Date, expectedEndAt: Date, targetMinutes: Int) {}
    func cancelWorktimeTarget(workDate: Date) {}
}
