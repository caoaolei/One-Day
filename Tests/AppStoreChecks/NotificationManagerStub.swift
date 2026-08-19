import Foundation

protocol TaskNotificationManaging: Sendable {
    func sendFocusReminder(taskTitle: String)
    func scheduleEstimateReached(taskID: UUID, taskTitle: String, after seconds: Int)
    func cancelEstimateReminder(taskID: UUID)
}

final class NotificationManager: TaskNotificationManaging, @unchecked Sendable {
    static let shared = NotificationManager()
    func sendFocusReminder(taskTitle: String) {}
    func scheduleEstimateReached(taskID: UUID, taskTitle: String, after seconds: Int) {}
    func cancelEstimateReminder(taskID: UUID) {}
}
