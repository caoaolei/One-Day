import Foundation
import UserNotifications

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
    private let center = UNUserNotificationCenter.current()

    private init() {}

    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func requestAndSchedule(settings: AppSettings) async -> Bool {
        guard await requestAuthorization() else { return false }
        do {
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

    func scheduleWorktimeTarget(
        workDate: Date,
        startAt: Date,
        expectedEndAt: Date,
        targetMinutes: Int
    ) {
        let identifier = worktimeIdentifier(for: workDate)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard expectedEndAt > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "今日目标工时已达到"
        content.body = "从 \(DateFormatter.yiRiTime.string(from: startAt)) 开始，已达到 \(targetMinutes.worktimeTargetText)，辛苦了。"
        content.sound = .default
        let components = Calendar.yiRi.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: expectedEndAt
        )
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        center.add(request)
    }

    func cancelWorktimeTarget(workDate: Date) {
        center.removePendingNotificationRequests(withIdentifiers: [worktimeIdentifier(for: workDate)])
    }

    private func worktimeIdentifier(for workDate: Date) -> String {
        let components = Calendar.yiRi.dateComponents([.year, .month, .day], from: workDate)
        return "worktime-target-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}
