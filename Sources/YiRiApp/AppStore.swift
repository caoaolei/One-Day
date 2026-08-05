import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var meetings: [MeetingItem] = []
    @Published private(set) var templates: [TaskTemplate] = []
    @Published private(set) var reviews: [DailyReview] = []
    @Published var settings = AppSettings()
    @Published private(set) var activeTaskID: UUID?
    @Published private(set) var timerStartedAt: Date?
    @Published private(set) var timerAccumulatedSeconds = 0

    private let dataURL: URL

    init() {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("YiRi", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        dataURL = directory.appendingPathComponent("data.json")
        load()
    }

    var activeTask: TaskItem? {
        guard let activeTaskID else { return nil }
        return tasks.first(where: { $0.id == activeTaskID })
    }

    func tasks(on date: Date) -> [TaskItem] {
        tasks
            .filter { item in
                guard let scheduledDate = item.scheduledDate else { return false }
                return Calendar.yiRi.isDate(scheduledDate, inSameDayAs: date)
            }
            .sorted { left, right in
                if left.isCompleted != right.isCompleted { return !left.isCompleted }
                return left.createdAt < right.createdAt
            }
    }

    func meetings(on date: Date) -> [MeetingItem] {
        meetings
            .filter { Calendar.yiRi.isDate($0.startDate, inSameDayAs: date) }
            .sorted { $0.startDate < $1.startDate }
    }

    func review(on date: Date) -> DailyReview? {
        reviews.first { Calendar.yiRi.isDate($0.date, inSameDayAs: date) }
    }

    func addTask(title: String, category: String, estimatedMinutes: Int, date: Date?) {
        let task = TaskItem(
            title: title,
            category: category,
            estimatedMinutes: max(5, estimatedMinutes),
            scheduledDate: date?.startOfLocalDay
        )
        tasks.append(task)
        save()
    }

    func updateTask(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
        save()
    }

    func setCompleted(_ id: UUID, completed: Bool) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isCompleted = completed
        tasks[index].completedAt = completed ? Date() : nil
        if completed, activeTaskID == id { finishActiveTask() }
        save()
    }

    func moveTask(_ id: UUID, to date: Date?) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].scheduledDate = date?.startOfLocalDay
        save()
    }

    func deleteTask(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        if activeTaskID == id {
            NotificationManager.shared.cancelEstimateReminder(taskID: id)
            activeTaskID = nil
            timerStartedAt = nil
            timerAccumulatedSeconds = 0
        }
        save()
    }

    func startTask(_ id: UUID) {
        if activeTaskID != id {
            pauseActiveTask()
            activeTaskID = id
            timerAccumulatedSeconds = tasks.first(where: { $0.id == id })?.actualSeconds ?? 0
        }
        timerStartedAt = Date()
        save()

        if let task = tasks.first(where: { $0.id == id }) {
            let remaining = max(2, task.estimatedMinutes * 60 - timerAccumulatedSeconds)
            NotificationManager.shared.scheduleEstimateReached(taskID: id, taskTitle: task.title, after: remaining)
            if settings.remindDoNotDisturb {
                NotificationManager.shared.sendFocusReminder(taskTitle: task.title)
            }
        }
    }

    func elapsedSeconds(at now: Date = Date()) -> Int {
        guard let timerStartedAt else { return timerAccumulatedSeconds }
        return timerAccumulatedSeconds + max(0, Int(now.timeIntervalSince(timerStartedAt)))
    }

    func pauseActiveTask() {
        guard let activeTaskID else { return }
        timerAccumulatedSeconds = elapsedSeconds()
        timerStartedAt = nil
        NotificationManager.shared.cancelEstimateReminder(taskID: activeTaskID)
        save()
    }

    func resumeActiveTask() {
        guard let activeTaskID, timerStartedAt == nil,
              let task = tasks.first(where: { $0.id == activeTaskID }) else { return }
        timerStartedAt = Date()
        let remaining = max(2, task.estimatedMinutes * 60 - timerAccumulatedSeconds)
        NotificationManager.shared.scheduleEstimateReached(taskID: activeTaskID, taskTitle: task.title, after: remaining)
        save()
    }

    func finishActiveTask() {
        guard let activeTaskID,
              let index = tasks.firstIndex(where: { $0.id == activeTaskID }) else { return }
        let elapsed = elapsedSeconds()
        NotificationManager.shared.cancelEstimateReminder(taskID: activeTaskID)
        tasks[index].actualSeconds = elapsed
        tasks[index].isCompleted = true
        tasks[index].completedAt = Date()
        self.activeTaskID = nil
        timerStartedAt = nil
        timerAccumulatedSeconds = 0
        save()
    }

    func addMeeting(title: String, startDate: Date, durationMinutes: Int, location: String) {
        meetings.append(MeetingItem(
            title: title,
            startDate: startDate,
            durationMinutes: max(5, durationMinutes),
            location: location
        ))
        save()
    }

    func saveReview(note: String) {
        let today = Date().startOfLocalDay
        if let index = reviews.firstIndex(where: { Calendar.yiRi.isDate($0.date, inSameDayAs: today) }) {
            reviews[index].note = note
            reviews[index].savedAt = Date()
        } else {
            reviews.append(DailyReview(date: today, note: note))
        }

        let incomplete = tasks(on: today).filter { !$0.isCompleted }
        switch settings.carryOverPolicy {
        case .manual:
            break
        case .tomorrow:
            incomplete.forEach { moveTask($0.id, to: today.addingDays(1)) }
        case .backlog:
            incomplete.forEach { moveTask($0.id, to: nil) }
        }
        save()
    }

    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        save()
    }

    func setNotificationAuthorization(_ authorized: Bool) {
        settings.notificationsAuthorized = authorized
        save()
    }

    func addTemplate(name: String, detail: String, taskLines: [String], defaultMinutes: Int) {
        let entries = taskLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { TemplateTask(title: $0, category: "自定义", estimatedMinutes: defaultMinutes) }
        templates.append(TaskTemplate(name: name, detail: detail, tasks: entries))
        save()
    }

    func updateTemplate(_ template: TaskTemplate) {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return }
        templates[index] = template
        save()
    }

    func deleteTemplate(_ id: UUID) {
        templates.removeAll { $0.id == id && !$0.isBuiltIn }
        save()
    }

    @discardableResult
    func batchAdd(
        template: TaskTemplate,
        startDate: Date,
        endDate: Date,
        selectedTaskIDs: Set<UUID>,
        skipDuplicates: Bool
    ) -> Int {
        let start = startDate.startOfLocalDay
        let end = endDate.startOfLocalDay
        guard end >= start else { return 0 }
        let selected = template.tasks.filter { selectedTaskIDs.contains($0.id) }
        var added = 0
        var cursor = start
        var dayCount = 0

        while cursor <= end && dayCount < 92 {
            for entry in selected {
                let duplicate = tasks.contains { item in
                    item.title == entry.title && item.scheduledDate.map { Calendar.yiRi.isDate($0, inSameDayAs: cursor) } == true
                }
                if skipDuplicates && duplicate { continue }
                tasks.append(TaskItem(
                    title: entry.title,
                    category: entry.category,
                    estimatedMinutes: entry.estimatedMinutes,
                    scheduledDate: cursor
                ))
                added += 1
            }
            cursor = cursor.addingDays(1)
            dayCount += 1
        }
        save()
        return added
    }

    func autoEstimate(title: String, category: String) -> EstimateSuggestion {
        let historical = tasks.filter { item in
            guard item.actualSeconds >= 60 else { return false }
            if item.category == category { return true }
            return Self.sharesKeyword(item.title, title)
        }
        let minutes = historical.map { max(5, $0.actualSeconds / 60) }.sorted()
        if !minutes.isEmpty {
            let median = minutes[minutes.count / 2]
            let rounded = max(5, Int((Double(median) / 5.0).rounded()) * 5)
            return EstimateSuggestion(minutes: rounded, reason: "基于 \(minutes.count) 次相似任务的中位用时")
        }

        let fallback: Int
        if title.contains("邮件") || title.contains("消息") || title.contains("回复") {
            fallback = 30
        } else if title.contains("写") || title.contains("方案") || title.contains("报告") {
            fallback = 90
        } else if title.contains("会议") || title.contains("评审") || title.contains("沟通") {
            fallback = 60
        } else {
            fallback = 45
        }
        return EstimateSuggestion(minutes: fallback, reason: "历史数据不足，按任务类型给出初始建议")
    }

    private static func sharesKeyword(_ left: String, _ right: String) -> Bool {
        let keywords = ["邮件", "复盘", "原型", "写作", "报告", "会议", "整理", "设计", "评审"]
        return keywords.contains { left.contains($0) && right.contains($0) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: dataURL) else {
            seedInitialData()
            save()
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(PersistedState.self, from: data)
            tasks = state.tasks
            meetings = state.meetings
            templates = state.templates
            reviews = state.reviews
            settings = state.settings
            activeTaskID = state.activeTaskID
            timerStartedAt = state.timerStartedAt
            timerAccumulatedSeconds = state.timerAccumulatedSeconds
        } catch {
            seedInitialData()
            save()
        }
    }

    private func save() {
        let state = PersistedState(
            tasks: tasks,
            meetings: meetings,
            templates: templates,
            reviews: reviews,
            settings: settings,
            activeTaskID: activeTaskID,
            timerStartedAt: timerStartedAt,
            timerAccumulatedSeconds: timerAccumulatedSeconds
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(state) {
            try? data.write(to: dataURL, options: .atomic)
        }
    }

    private func seedInitialData() {
        let today = Date().startOfLocalDay
        tasks = [
            TaskItem(title: "梳理本周优先级", category: "规划", estimatedMinutes: 30, actualSeconds: 26 * 60, scheduledDate: today, isCompleted: true, completedAt: Date()),
            TaskItem(title: "完成每日复盘 App MVP", category: "深度工作", estimatedMinutes: 90, scheduledDate: today),
            TaskItem(title: "回复项目邮件", category: "日常", estimatedMinutes: 30, scheduledDate: today),
            TaskItem(title: "撰写季度复盘初稿", category: "写作", estimatedMinutes: 120, scheduledDate: today),
            TaskItem(title: "整理项目邮件", category: "日常", estimatedMinutes: 30, actualSeconds: 24 * 60, scheduledDate: today.addingDays(-3), isCompleted: true, completedAt: today.addingDays(-3)),
            TaskItem(title: "回复合作邮件", category: "日常", estimatedMinutes: 30, actualSeconds: 31 * 60, scheduledDate: today.addingDays(-5), isCompleted: true, completedAt: today.addingDays(-5)),
            TaskItem(title: "写产品方案", category: "写作", estimatedMinutes: 90, actualSeconds: 102 * 60, scheduledDate: today.addingDays(-6), isCompleted: true, completedAt: today.addingDays(-6))
        ]
        templates = [
            TaskTemplate(
                name: "工作日启动",
                detail: "默认的每日计划模版",
                tasks: [
                    TemplateTask(title: "梳理今日优先级", category: "规划", estimatedMinutes: 30),
                    TemplateTask(title: "处理邮件与消息", category: "日常", estimatedMinutes: 25),
                    TemplateTask(title: "晚间复盘", category: "复盘", estimatedMinutes: 10)
                ],
                isBuiltIn: true
            ),
            TaskTemplate(
                name: "无会专注日",
                detail: "为深度工作预留完整时段",
                tasks: [
                    TemplateTask(title: "深度工作时段一", category: "深度工作", estimatedMinutes: 90),
                    TemplateTask(title: "深度工作时段二", category: "深度工作", estimatedMinutes: 90),
                    TemplateTask(title: "当日总结", category: "复盘", estimatedMinutes: 15)
                ],
                isBuiltIn: true
            )
        ]
        let tenAM = Calendar.yiRi.date(bySettingHour: 10, minute: 0, second: 0, of: today) ?? today
        meetings = [MeetingItem(title: "产品周会", startDate: tenAM, durationMinutes: 45, location: "会议室 A")]
        reviews = []
        settings = AppSettings()
        activeTaskID = nil
        timerStartedAt = nil
        timerAccumulatedSeconds = 0
    }
}
