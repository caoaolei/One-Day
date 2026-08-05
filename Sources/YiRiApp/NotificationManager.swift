import Foundation
import UserNotifications

final class NotificationManager: @unchecked Sendable {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    private init() {}

    func requestAndSchedule(settings: AppSettings) async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return false }
            try await scheduleDailyReminders(settings: settings)
            return true
        } catch {
            return false
        }
    }

    func scheduleDailyReminders(settings: AppSettings) async throws {
        center.removePendingNotificationRequests(withIdentifiers: ["morning-plan", "evening-review"])

        let morning = UNMutableNotificationContent()
        morning.title = "开始今天的计划"
        morning.body = "列出今天要做的事情、预计时间和会议。"
        morning.sound = .default

        let evening = UNMutableNotificationContent()
        evening.title = "该做今日复盘了"
        evening.body = "确认完成的任务，补充备注，并处理未完成事项。"
        evening.sound = .default

        let morningComponents = DateComponents(
            hour: settings.morningReminderMinutes / 60,
            minute: settings.morningReminderMinutes % 60
        )
        let eveningComponents = DateComponents(
            hour: settings.eveningReminderMinutes / 60,
            minute: settings.eveningReminderMinutes % 60
        )

        let morningRequest = UNNotificationRequest(
            identifier: "morning-plan",
            content: morning,
            trigger: UNCalendarNotificationTrigger(dateMatching: morningComponents, repeats: true)
        )
        let eveningRequest = UNNotificationRequest(
            identifier: "evening-review",
            content: evening,
            trigger: UNCalendarNotificationTrigger(dateMatching: eveningComponents, repeats: true)
        )

        try await center.add(morningRequest)
        try await center.add(eveningRequest)
    }

    func sendFocusReminder(taskTitle: String) {
        let content = UNMutableNotificationContent()
        content.title = "专注计时已开始"
        content.body = "正在进行“\(taskTitle)”，记得开启勿扰模式。"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "focus-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        center.add(request)
    }

    func scheduleEstimateReached(taskID: UUID, taskTitle: String, after seconds: Int) {
        let identifier = "estimate-\(taskID.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard seconds > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = "已达到预计时间"
        content.body = "“\(taskTitle)”可以继续进行，也可以现在完成并记录实际用时。"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        )
        center.add(request)
    }

    func cancelEstimateReminder(taskID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: ["estimate-\(taskID.uuidString)"])
    }
}
