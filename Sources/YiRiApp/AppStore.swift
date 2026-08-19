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
    @Published private(set) var persistenceIssue: PersistenceIssue?

    private let dataURL: URL
    private let notificationManager: any TaskNotificationManaging
    private let nowProvider: () -> Date
    private var persistenceBlocked = false

    init(
        dataURL: URL? = nil,
        notificationManager: any TaskNotificationManaging = NotificationManager.shared,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        let fileManager = FileManager.default
        let resolvedURL: URL
        if let dataURL {
            resolvedURL = dataURL
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            resolvedURL = support
                .appendingPathComponent("YiRi", isDirectory: true)
                .appendingPathComponent("data.json")
        }
        self.dataURL = resolvedURL
        self.notificationManager = notificationManager
        self.nowProvider = nowProvider
        do {
            try fileManager.createDirectory(
                at: resolvedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            persistenceBlocked = true
            persistenceIssue = PersistenceIssue(
                title: "无法创建数据目录",
                message: "一日暂时不能保存数据：\(error.localizedDescription)"
            )
        }
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

    func overdueTasks(referenceDate: Date = Date()) -> [TaskItem] {
        let today = referenceDate.startOfLocalDay
        return tasks
            .filter { item in
                guard !item.isCompleted, let scheduledDate = item.scheduledDate else { return false }
                return scheduledDate.startOfLocalDay < today
            }
            .sorted {
                ($0.scheduledDate ?? .distantPast) > ($1.scheduledDate ?? .distantPast)
            }
    }

    func unplannedOrUpcomingTasks(referenceDate: Date = Date()) -> [TaskItem] {
        let tomorrow = referenceDate.addingDays(1)
        return tasks
            .filter { item in
                guard !item.isCompleted else { return false }
                guard let scheduledDate = item.scheduledDate else { return true }
                return scheduledDate.startOfLocalDay >= tomorrow
            }
            .sorted { left, right in
                switch (left.scheduledDate, right.scheduledDate) {
                case (nil, nil):
                    return left.createdAt < right.createdAt
                case (nil, _):
                    return true
                case (_, nil):
                    return false
                case let (leftDate?, rightDate?):
                    return leftDate < rightDate
                }
            }
    }

    func completedToday(referenceDate: Date = Date()) -> [TaskItem] {
        tasks
            .filter { item in
                guard item.isCompleted, let completedAt = item.completedAt else { return false }
                return Calendar.yiRi.isDate(completedAt, inSameDayAs: referenceDate)
            }
            .sorted {
                ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
            }
    }

    func earlierCompleted(referenceDate: Date = Date()) -> [TaskItem] {
        tasks
            .filter { item in
                guard item.isCompleted else { return false }
                guard let completedAt = item.completedAt else { return true }
                return !Calendar.yiRi.isDate(completedAt, inSameDayAs: referenceDate)
            }
            .sorted {
                switch ($0.completedAt, $1.completedAt) {
                case let (left?, right?):
                    return left > right
                case (nil, nil):
                    return $0.createdAt > $1.createdAt
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                }
            }
    }

    func earlierCompletedCount(referenceDate: Date = Date()) -> Int {
        tasks.reduce(into: 0) { count, item in
            guard item.isCompleted else { return }
            guard let completedAt = item.completedAt else {
                count += 1
                return
            }
            if !Calendar.yiRi.isDate(completedAt, inSameDayAs: referenceDate) {
                count += 1
            }
        }
    }

    @discardableResult
    func moveTask(_ id: UUID, to lane: BoardLane, referenceDate: Date? = nil) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
        let now = referenceDate ?? nowProvider()
        let today = now.startOfLocalDay

        switch lane {
        case .yesterday:
            let isAlreadyOverdue = !tasks[index].isCompleted
                && (tasks[index].scheduledDate?.startOfLocalDay ?? .distantFuture) < today
            guard !isAlreadyOverdue else { return false }
            tasks[index].isCompleted = false
            tasks[index].completedAt = nil
            if (tasks[index].scheduledDate?.startOfLocalDay ?? .distantFuture) >= today {
                tasks[index].scheduledDate = today.addingDays(-1)
            }

        case .todayPending:
            let isAlreadyToday = !tasks[index].isCompleted
                && tasks[index].scheduledDate.map { Calendar.yiRi.isDate($0, inSameDayAs: today) } == true
            guard !isAlreadyToday else { return false }
            tasks[index].isCompleted = false
            tasks[index].completedAt = nil
            tasks[index].scheduledDate = today

        case .todayCompleted:
            let isAlreadyCompletedToday = tasks[index].isCompleted
                && tasks[index].completedAt.map { Calendar.yiRi.isDate($0, inSameDayAs: today) } == true
            guard !isAlreadyCompletedToday else { return false }
            if activeTaskID == id {
                finishActiveTask()
                return true
            }
            tasks[index].isCompleted = true
            tasks[index].completedAt = now
        }

        save()
        return true
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
        if activeTaskID == task.id, timerStartedAt != nil {
            scheduleEstimateReminder(for: task)
        }
        save()
    }

    func setCompleted(_ id: UUID, completed: Bool) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isCompleted = completed
        tasks[index].completedAt = completed ? nowProvider() : nil
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
            notificationManager.cancelEstimateReminder(taskID: id)
            activeTaskID = nil
            timerStartedAt = nil
            timerAccumulatedSeconds = 0
        }
        save()
    }

    func startTask(_ id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }), !task.isCompleted else { return }
        if activeTaskID == id {
            if timerStartedAt == nil { resumeActiveTask() }
            return
        }

        pauseActiveTask()
        activeTaskID = id
        timerAccumulatedSeconds = task.actualSeconds
        timerStartedAt = nowProvider()
        save()

        scheduleEstimateReminder(for: task)
        if settings.remindDoNotDisturb {
            notificationManager.sendFocusReminder(taskTitle: task.title)
        }
    }

    func elapsedSeconds(at now: Date? = nil) -> Int {
        guard let timerStartedAt else { return timerAccumulatedSeconds }
        let current = now ?? nowProvider()
        return timerAccumulatedSeconds + max(0, Int(current.timeIntervalSince(timerStartedAt)))
    }

    func pauseActiveTask() {
        guard let activeTaskID else { return }
        let elapsed = elapsedSeconds()
        timerAccumulatedSeconds = elapsed
        if let index = tasks.firstIndex(where: { $0.id == activeTaskID }) {
            tasks[index].actualSeconds = elapsed
        }
        timerStartedAt = nil
        notificationManager.cancelEstimateReminder(taskID: activeTaskID)
        save()
    }

    func resumeActiveTask() {
        guard let activeTaskID, timerStartedAt == nil,
              let task = tasks.first(where: { $0.id == activeTaskID }) else { return }
        timerStartedAt = nowProvider()
        scheduleEstimateReminder(for: task)
        save()
    }

    func finishActiveTask() {
        guard let activeTaskID,
              let index = tasks.firstIndex(where: { $0.id == activeTaskID }) else { return }
        let elapsed = elapsedSeconds()
        notificationManager.cancelEstimateReminder(taskID: activeTaskID)
        tasks[index].actualSeconds = elapsed
        tasks[index].isCompleted = true
        tasks[index].completedAt = nowProvider()
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

    func updateMeeting(_ meeting: MeetingItem) {
        guard let index = meetings.firstIndex(where: { $0.id == meeting.id }) else { return }
        meetings[index] = meeting
        save()
    }

    func deleteMeeting(_ id: UUID) {
        meetings.removeAll { $0.id == id }
        save()
    }

    func saveReview(note: String) {
        let now = nowProvider()
        let today = now.startOfLocalDay
        if let index = reviews.firstIndex(where: { Calendar.yiRi.isDate($0.date, inSameDayAs: today) }) {
            reviews[index].note = note
            reviews[index].savedAt = now
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

    func updateDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.displayName = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func setNotificationAuthorization(_ authorized: Bool) {
        guard settings.notificationsAuthorized != authorized else { return }
        settings.notificationsAuthorized = authorized
        save()
    }

    func clearPersistenceIssue() {
        persistenceIssue = nil
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
            let middle = minutes.count / 2
            let median = minutes.count.isMultiple(of: 2)
                ? Double(minutes[middle - 1] + minutes[middle]) / 2.0
                : Double(minutes[middle])
            let rounded = max(5, Int((median / 5.0).rounded()) * 5)
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
        guard FileManager.default.fileExists(atPath: dataURL.path) else {
            seedInitialData()
            save()
            return
        }
        do {
            let data = try Data(contentsOf: dataURL)
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
            recoverFromUnreadableData()
        }
    }

    private func save() {
        guard !persistenceBlocked else { return }
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
        do {
            let data = try encoder.encode(state)
            try data.write(to: dataURL, options: .atomic)
        } catch {
            persistenceIssue = PersistenceIssue(
                title: "数据保存失败",
                message: "请检查磁盘空间或文件权限。错误：\(error.localizedDescription)"
            )
        }
    }

    private func recoverFromUnreadableData() {
        let backupURL = dataURL
            .deletingLastPathComponent()
            .appendingPathComponent("data-corrupt-\(Int(nowProvider().timeIntervalSince1970)).json")
        do {
            try FileManager.default.copyItem(at: dataURL, to: backupURL)
            seedInitialData()
            save()
            persistenceIssue = PersistenceIssue(
                title: "数据文件需要恢复",
                message: "原数据无法读取，已备份到 \(backupURL.lastPathComponent)。一日已创建一份新的空白数据文件。"
            )
        } catch {
            seedInitialData()
            persistenceBlocked = true
            persistenceIssue = PersistenceIssue(
                title: "数据文件无法读取",
                message: "为了保护原文件，一日已停止写入。请先备份 \(dataURL.path)。错误：\(error.localizedDescription)"
            )
        }
    }

    private func scheduleEstimateReminder(for task: TaskItem) {
        let remaining = task.estimatedMinutes * 60 - elapsedSeconds()
        if remaining > 1 {
            notificationManager.scheduleEstimateReached(
                taskID: task.id,
                taskTitle: task.title,
                after: remaining
            )
        } else {
            notificationManager.cancelEstimateReminder(taskID: task.id)
        }
    }

    private func seedInitialData() {
        tasks = []
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
        meetings = []
        reviews = []
        settings = AppSettings()
        activeTaskID = nil
        timerStartedAt = nil
        timerAccumulatedSeconds = 0
    }
}
