import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var meetings: [MeetingItem] = []
    @Published private(set) var templates: [TaskTemplate] = []
    @Published private(set) var reviews: [DailyReview] = []
    @Published var settings = AppSettings()
    static let defaultFocusSlotCount = 2
    @Published private(set) var focusSlots: [FocusSession?] = Array(repeating: nil, count: defaultFocusSlotCount)
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

    var hasEmptyFocusSlot: Bool { focusSlots.contains { $0 == nil } }
    var hasRunningFocusTasks: Bool { focusSlots.contains { $0?.startedAt != nil } }
    var hasPausedFocusTasks: Bool {
        focusSlots.contains { session in
            guard let session else { return false }
            return session.startedAt == nil
        }
    }

    func focusSlot(for taskID: UUID) -> Int? {
        focusSlots.firstIndex { $0?.taskID == taskID }
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

    func boardBacklogTasks(referenceDate: Date = Date()) -> [TaskItem] {
        let today = referenceDate.startOfLocalDay
        return tasks
            .filter { item in
                guard !item.isCompleted else { return false }
                guard let scheduledDate = item.scheduledDate else { return true }
                return !Calendar.yiRi.isDate(scheduledDate, inSameDayAs: today)
            }
            .sorted { left, right in
                let leftRank = backlogRank(for: left, today: today)
                let rightRank = backlogRank(for: right, today: today)
                if leftRank != rightRank { return leftRank < rightRank }

                switch (left.scheduledDate, right.scheduledDate) {
                case let (leftDate?, rightDate?):
                    return leftRank == 0 ? leftDate > rightDate : leftDate < rightDate
                case (nil, nil):
                    return left.createdAt < right.createdAt
                case (nil, _):
                    return true
                case (_, nil):
                    return false
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

    func completedTasks() -> [TaskItem] {
        tasks
            .filter(\.isCompleted)
            .sorted { left, right in
                switch (left.completedAt, right.completedAt) {
                case let (leftDate?, rightDate?):
                    return leftDate > rightDate
                case (nil, nil):
                    return left.createdAt > right.createdAt
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                }
            }
    }

    func completedDayGroups() -> [HistoryDayGroup] {
        HistoryInsights.dayGroups(from: completedTasks())
    }

    func historyTopics() -> [HistoryTopic] {
        HistoryInsights.topics(from: completedTasks())
    }

    func futureWorkdayPlan(
        title: String,
        workdayCount: Int,
        skipDuplicates: Bool,
        referenceDate: Date? = nil
    ) -> FutureWorkdayPlan {
        let count = min(92, max(1, workdayCount))
        let dates = Self.nextWorkdays(after: referenceDate ?? nowProvider(), count: count)
        guard skipDuplicates else {
            return FutureWorkdayPlan(dates: dates, creatableDates: dates, skippedDuplicateCount: 0)
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let creatableDates = dates.filter { date in
            !tasks.contains { task in
                task.title == trimmedTitle
                    && task.scheduledDate.map { Calendar.yiRi.isDate($0, inSameDayAs: date) } == true
            }
        }
        return FutureWorkdayPlan(
            dates: dates,
            creatableDates: creatableDates,
            skippedDuplicateCount: dates.count - creatableDates.count
        )
    }

    @discardableResult
    func addFutureWorkdayTasks(
        title: String,
        category: String,
        estimatedMinutes: Int,
        workdayCount: Int,
        skipDuplicates: Bool,
        subtasks: [TaskSubtaskDraft] = [],
        referenceDate: Date? = nil
    ) -> FutureTaskCreationResult {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return FutureTaskCreationResult(createdCount: 0, skippedDuplicateCount: 0, firstDate: nil, lastDate: nil)
        }
        let plan = futureWorkdayPlan(
            title: trimmedTitle,
            workdayCount: workdayCount,
            skipDuplicates: skipDuplicates,
            referenceDate: referenceDate
        )
        for date in plan.creatableDates {
            let parent = TaskItem(
                title: trimmedTitle,
                category: category,
                estimatedMinutes: max(5, estimatedMinutes),
                scheduledDate: date.startOfLocalDay
            )
            tasks.append(parent)
            appendSubtasks(subtasks, to: parent, date: date)
        }
        save()
        return FutureTaskCreationResult(
            createdCount: plan.creatableDates.count,
            skippedDuplicateCount: plan.skippedDuplicateCount,
            firstDate: plan.dates.first,
            lastDate: plan.dates.last
        )
    }

    func renameHistoryTopic(_ topic: HistoryTopic, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let groupID = materializedGroupID(for: topic)
        assignHistoryGroup(taskIDs: Set(topic.tasks.map(\.id)), groupID: groupID, name: trimmedName)
    }

    func moveHistoryTask(_ taskID: UUID, to topic: HistoryTopic) {
        let groupID = materializedGroupID(for: topic)
        let targetIDs = Set(topic.tasks.map(\.id)).union([taskID])
        assignHistoryGroup(taskIDs: targetIDs, groupID: groupID, name: topic.name)
    }

    func splitHistoryTask(_ taskID: UUID, newTopicName: String) {
        let trimmedName = newTopicName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        assignHistoryGroup(taskIDs: [taskID], groupID: UUID(), name: trimmedName)
    }

    func mergeHistoryTopic(_ source: HistoryTopic, into target: HistoryTopic) {
        let groupID = materializedGroupID(for: target)
        let taskIDs = Set(source.tasks.map(\.id)).union(target.tasks.map(\.id))
        assignHistoryGroup(taskIDs: taskIDs, groupID: groupID, name: target.name)
    }

    @discardableResult
    func moveTask(_ id: UUID, to lane: BoardLane, referenceDate: Date? = nil) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
        let now = referenceDate ?? nowProvider()
        let today = now.startOfLocalDay

        switch lane {
        case .backlog:
            let isAlreadyInBacklog = !tasks[index].isCompleted
                && tasks[index].scheduledDate.map {
                    !Calendar.yiRi.isDate($0, inSameDayAs: today)
                } != false
            guard !isAlreadyInBacklog else { return false }
            tasks[index].isCompleted = false
            tasks[index].completedAt = nil
            tasks[index].scheduledDate = nil

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
            releaseFocusSlot(for: index, at: now)
            tasks[index].isCompleted = true
            tasks[index].completedAt = now
        }

        save()
        return true
    }

    private func backlogRank(for task: TaskItem, today: Date) -> Int {
        guard let scheduledDate = task.scheduledDate else { return 1 }
        return scheduledDate.startOfLocalDay < today ? 0 : 2
    }

    func meetings(on date: Date) -> [MeetingItem] {
        meetings
            .filter { Calendar.yiRi.isDate($0.startDate, inSameDayAs: date) }
            .sorted { $0.startDate < $1.startDate }
    }

    func review(on date: Date) -> DailyReview? {
        reviews.first { Calendar.yiRi.isDate($0.date, inSameDayAs: date) }
    }

    func isDayFinalized(_ date: Date) -> Bool {
        review(on: date) != nil
    }

    @discardableResult
    func addTask(
        title: String,
        category: String,
        estimatedMinutes: Int,
        date: Date?,
        parentTaskID: UUID? = nil
    ) -> TaskItem {
        let task = TaskItem(
            title: title,
            category: category,
            estimatedMinutes: max(5, estimatedMinutes),
            scheduledDate: date?.startOfLocalDay,
            parentTaskID: parentTaskID
        )
        tasks.append(task)
        save()
        return task
    }

    @discardableResult
    func addTaskWithSubtasks(
        title: String,
        category: String,
        estimatedMinutes: Int,
        date: Date?,
        subtasks: [TaskSubtaskDraft]
    ) -> TaskItem {
        let parent = TaskItem(
            title: title,
            category: category,
            estimatedMinutes: max(5, estimatedMinutes),
            scheduledDate: date?.startOfLocalDay
        )
        tasks.append(parent)
        appendSubtasks(subtasks, to: parent, date: date)
        save()
        return parent
    }

    @discardableResult
    func addSubtask(
        to parent: TaskItem,
        title: String,
        estimatedMinutes: Int,
        date: Date? = nil
    ) -> TaskItem {
        addTask(
            title: title,
            category: parent.category,
            estimatedMinutes: estimatedMinutes,
            date: date ?? parent.scheduledDate,
            parentTaskID: parent.id
        )
    }

    func parentTask(for task: TaskItem) -> TaskItem? {
        guard let parentTaskID = task.parentTaskID else { return nil }
        return tasks.first(where: { $0.id == parentTaskID })
    }

    func subtasks(of task: TaskItem) -> [TaskItem] {
        tasks.filter { $0.parentTaskID == task.id }
    }

    private func appendSubtasks(_ drafts: [TaskSubtaskDraft], to parent: TaskItem, date: Date?) {
        for draft in drafts {
            let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { continue }
            tasks.append(TaskItem(
                title: trimmedTitle,
                category: parent.category,
                estimatedMinutes: max(5, draft.estimatedMinutes),
                scheduledDate: date?.startOfLocalDay,
                parentTaskID: parent.id
            ))
        }
    }

    private static func nextWorkdays(after referenceDate: Date, count: Int) -> [Date] {
        guard count > 0 else { return [] }
        var dates: [Date] = []
        var cursor = referenceDate.startOfLocalDay
        while dates.count < count {
            cursor = cursor.addingDays(1)
            let weekday = Calendar.yiRi.component(.weekday, from: cursor)
            if (2...6).contains(weekday) { dates.append(cursor) }
        }
        return dates
    }

    private func materializedGroupID(for topic: HistoryTopic) -> UUID {
        if let groupID = topic.manualGroupID { return groupID }
        let groupID = UUID()
        assignHistoryGroup(
            taskIDs: Set(topic.tasks.map(\.id)),
            groupID: groupID,
            name: topic.name,
            shouldSave: false
        )
        return groupID
    }

    private func assignHistoryGroup(
        taskIDs: Set<UUID>,
        groupID: UUID,
        name: String,
        shouldSave: Bool = true
    ) {
        for index in tasks.indices where taskIDs.contains(tasks[index].id) {
            tasks[index].historyGroupID = groupID
            tasks[index].historyGroupName = name
        }
        if shouldSave { save() }
    }

    func updateTask(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var updated = task
        if let slot = focusSlot(for: task.id) {
            if task.isCompleted { releaseFocusSlot(for: index, at: nowProvider()) }
            updated.actualSeconds = tasks[index].actualSeconds
            tasks[index] = updated
            if focusSlots[slot]?.startedAt != nil { scheduleEstimateReminder(for: updated) }
        } else {
            tasks[index] = updated
        }
        save()
    }

    func setCompleted(_ id: UUID, completed: Bool) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let now = nowProvider()
        if completed { releaseFocusSlot(for: index, at: now) }
        tasks[index].isCompleted = completed
        tasks[index].completedAt = completed ? now : nil
        save()
    }

    func moveTask(_ id: UUID, to date: Date?) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].scheduledDate = date?.startOfLocalDay
        save()
    }

    func deleteTask(_ id: UUID) {
        for index in tasks.indices where tasks[index].parentTaskID == id {
            tasks[index].parentTaskID = nil
        }
        tasks.removeAll { $0.id == id }
        if let slot = focusSlot(for: id) {
            focusSlots[slot] = nil
            notificationManager.cancelEstimateReminder(taskID: id)
        }
        save()
    }

    func addFocusSlot() {
        focusSlots.append(nil)
        save()
    }

    func removeEmptyFocusSlot(_ slot: Int) {
        guard focusSlots.count > Self.defaultFocusSlotCount,
              focusSlots.indices.contains(slot), focusSlots[slot] == nil else { return }
        focusSlots.remove(at: slot)
        save()
    }

    @discardableResult
    func startTodayTask(_ id: UUID, in slot: Int) -> Bool {
        let now = nowProvider()
        guard focusSlots.indices.contains(slot), focusSlots[slot] == nil,
              focusSlot(for: id) == nil, !isDayFinalized(now),
              tasks(on: now).contains(where: { $0.id == id && !$0.isCompleted }) else { return false }
        startTask(id, in: slot)
        return true
    }

    func startTask(_ id: UUID, in requestedSlot: Int? = nil) {
        guard let task = tasks.first(where: { $0.id == id }), !task.isCompleted else { return }
        if let slot = focusSlot(for: id) {
            if requestedSlot == nil || requestedSlot == slot { resumeTask(id) }
            return
        }

        if requestedSlot == nil, !hasEmptyFocusSlot { focusSlots.append(nil) }
        guard let slot = requestedSlot ?? focusSlots.firstIndex(where: { $0 == nil }),
              focusSlots.indices.contains(slot), focusSlots[slot] == nil else { return }
        focusSlots[slot] = FocusSession(taskID: id, startedAt: nowProvider())
        save()

        scheduleEstimateReminder(for: task)
        if settings.remindDoNotDisturb {
            notificationManager.sendFocusReminder(taskTitle: task.title)
        }
    }

    func elapsedSeconds(for task: TaskItem, at now: Date? = nil) -> Int {
        let accumulated = max(0, task.actualSeconds)
        guard let slot = focusSlot(for: task.id), let startedAt = focusSlots[slot]?.startedAt else {
            return accumulated
        }
        return accumulated + max(0, Int((now ?? nowProvider()).timeIntervalSince(startedAt)))
    }

    func pauseTask(_ id: UUID) {
        guard let slot = focusSlot(for: id) else { return }
        pauseFocusSlots([slot])
    }

    func pauseAllFocusTasks() {
        pauseFocusSlots(focusSlots.indices)
    }

    private func pauseFocusSlots(_ slots: some Sequence<Int>) {
        let now = nowProvider()
        var didPause = false
        for slot in slots {
            guard let session = focusSlots[slot], session.startedAt != nil,
                  let index = tasks.firstIndex(where: { $0.id == session.taskID }) else { continue }
            tasks[index].actualSeconds = elapsedSeconds(for: tasks[index], at: now)
            focusSlots[slot]?.startedAt = nil
            notificationManager.cancelEstimateReminder(taskID: session.taskID)
            didPause = true
        }
        if didPause { save() }
    }

    func resumeTask(_ id: UUID) {
        guard let slot = focusSlot(for: id) else { return }
        resumeFocusSlots([slot])
    }

    func resumeAllFocusTasks() {
        resumeFocusSlots(focusSlots.indices)
    }

    private func resumeFocusSlots(_ slots: some Sequence<Int>) {
        let now = nowProvider()
        var didResume = false
        for slot in slots {
            guard let session = focusSlots[slot], session.startedAt == nil,
                  let task = tasks.first(where: { $0.id == session.taskID && !$0.isCompleted }) else { continue }
            focusSlots[slot]?.startedAt = now
            scheduleEstimateReminder(for: task, at: now)
            didResume = true
        }
        if didResume { save() }
    }

    func stopTask(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }), focusSlot(for: id) != nil else { return }
        releaseFocusSlot(for: index, at: nowProvider())
        save()
    }

    func stopAllFocusTasks() {
        let assignedIDs = Set(focusSlots.compactMap { $0?.taskID })
        guard !assignedIDs.isEmpty else { return }
        let now = nowProvider()
        for index in tasks.indices where assignedIDs.contains(tasks[index].id) {
            releaseFocusSlot(for: index, at: now)
        }
        save()
    }

    private func releaseFocusSlot(for taskIndex: Int, at now: Date) {
        let task = tasks[taskIndex]
        guard let slot = focusSlot(for: task.id) else { return }
        tasks[taskIndex].actualSeconds = elapsedSeconds(for: task, at: now)
        focusSlots[slot] = nil
        notificationManager.cancelEstimateReminder(taskID: task.id)
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

    @discardableResult
    func saveReview(note: String) -> Bool {
        let now = nowProvider()
        let today = now.startOfLocalDay
        guard review(on: today) == nil else { return false }
        var state = persistedState
        state.reviews.append(DailyReview(date: today, note: note, savedAt: now))
        let assignedIDs = Set(focusSlots.compactMap { $0?.taskID })
        for index in state.tasks.indices {
            let task = state.tasks[index]
            if assignedIDs.contains(task.id) {
                state.tasks[index].actualSeconds = elapsedSeconds(for: task, at: now)
            }
            guard !task.isCompleted, task.scheduledDate?.startOfLocalDay == today else { continue }
            switch settings.carryOverPolicy {
            case .manual: break
            case .tomorrow: state.tasks[index].scheduledDate = today.addingDays(1)
            case .backlog: state.tasks[index].scheduledDate = nil
            }
        }
        let emptySlots = Array<FocusSession?>(repeating: nil, count: focusSlots.count)
        state.focusSlots = emptySlots
        guard persist(state) else { return false }
        tasks = state.tasks
        reviews = state.reviews
        focusSlots = emptySlots
        for id in assignedIDs { notificationManager.cancelEstimateReminder(taskID: id) }
        return true
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

    func autoEstimate(title: String, category: String, excluding taskID: UUID? = nil) -> EstimateSuggestion {
        let history = estimateHistory().filter { $0.id != taskID }
        if let suggestion = historicalEstimate(title: title, category: category, history: history) {
            return suggestion
        }

        let normalizedTitle = NormalizedTitle(title).compact
        let fallback: Int
        if ["邮件", "消息", "回复", "email"].contains(where: normalizedTitle.contains) {
            fallback = 30
        } else if ["写", "方案", "报告"].contains(where: normalizedTitle.contains) {
            fallback = 90
        } else if ["会议", "评审", "沟通"].contains(where: normalizedTitle.contains) {
            fallback = 60
        } else {
            fallback = 45
        }
        return EstimateSuggestion(minutes: fallback, reason: "历史数据不足，按任务类型给出初始建议")
    }

    func recommendNextTask(at referenceDate: Date? = nil) -> NextTaskRecommendation {
        let now = referenceDate ?? nowProvider()
        let pending = tasks(on: now).filter { !$0.isCompleted }
        guard !pending.isEmpty else { return .noPendingTasks }
        let candidates = pending.filter { task in
            if let slot = focusSlot(for: task.id) { return focusSlots[slot]?.startedAt == nil }
            return true
        }
        if candidates.isEmpty { return .focusInProgress }

        // Include meetings already underway, even if they started the previous day.
        if meetings.contains(where: {
            $0.startDate <= now && $0.startDate.addingTimeInterval(Double($0.durationMinutes) * 60) > now
        }) {
            return .meetingInProgress
        }
        let nextMeeting = meetings
            .map(\.startDate)
            .filter { $0 > now && $0 < now.addingDays(1) }
            .min()
        let availableMinutes = nextMeeting.map { max(0, Int($0.timeIntervalSince(now) / 60) - 5) }
        let history = estimateHistory()
        var best: (task: TaskItem, minutes: Int, reason: String)?

        for task in candidates {
            let estimate = historicalEstimate(title: task.title, category: task.category, history: history)
                ?? EstimateSuggestion(minutes: max(5, task.estimatedMinutes), reason: "使用计划中的预计用时")
            let spentSeconds = max(0, task.actualSeconds)
            let remaining = Double(estimate.minutes) - Double(spentSeconds) / 60
            let projected = remaining > 0 ? Int(remaining.rounded(.up)) : estimate.minutes
            let reason: String
            if spentSeconds == 0 {
                reason = estimate.reason
            } else if remaining > 0 {
                reason = "\(estimate.reason)，已扣除已记录的专注时间"
            } else {
                reason = "\(estimate.reason)，已超过原估时，暂按完整时长预留"
            }
            if let availableMinutes, projected > availableMinutes { continue }
            if let best, projected <= best.minutes { continue }
            best = (task, projected, reason)
        }
        guard let best else { return .noTaskFits(availableMinutes: availableMinutes ?? 0) }
        return .task(best.task, minutes: best.minutes, estimateReason: best.reason, availableMinutes: availableMinutes)
    }

    private func estimateHistory() -> [TaskItem] {
        completedTasks().filter { $0.actualSeconds >= 60 }
    }

    private func historicalEstimate(title: String, category: String, history: [TaskItem]) -> EstimateSuggestion? {
        let normalized = NormalizedTitle(title).compact
        guard !normalized.isEmpty else { return nil }
        let exact = history.filter { NormalizedTitle($0.title).compact == normalized }
        if !exact.isEmpty { return medianEstimate(exact, source: "同名") }

        let similar = history.filter { HistoryInsights.titlesAreSimilar($0.title, title) }
        if !similar.isEmpty { return medianEstimate(similar, source: "名称相似的") }

        let sameCategory = history.filter { $0.category == category }
        guard !sameCategory.isEmpty else { return nil }
        return medianEstimate(sameCategory, source: "同分类的")
    }

    private func medianEstimate(_ tasks: [TaskItem], source: String) -> EstimateSuggestion {
        let minutes = tasks.prefix(12).map { Double($0.actualSeconds) / 60 }.sorted()
        let center = minutes.count / 2
        let median = minutes.count.isMultiple(of: 2)
            ? (minutes[center - 1] + minutes[center]) / 2
            : minutes[center]
        let rounded = min(480, max(5, (median / 5).rounded() * 5))
        return EstimateSuggestion(minutes: Int(rounded), reason: "参考最近 \(minutes.count) 条\(source)任务的实际用时")
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
            if let savedSlots = state.focusSlots {
                let pendingIDs = Set(tasks.filter { !$0.isCompleted }.map(\.id))
                var seen: Set<UUID> = []
                focusSlots = savedSlots.map { session in
                    guard let session, pendingIDs.contains(session.taskID), seen.insert(session.taskID).inserted else {
                        return nil
                    }
                    return session
                }
                while focusSlots.count < Self.defaultFocusSlotCount { focusSlots.append(nil) }
            } else if let id = state.activeTaskID,
                      let index = tasks.firstIndex(where: { $0.id == id && !$0.isCompleted }) {
                tasks[index].actualSeconds = max(0, state.timerAccumulatedSeconds)
                focusSlots[0] = FocusSession(taskID: id, startedAt: state.timerStartedAt)
            }
        } catch {
            recoverFromUnreadableData()
        }
    }

    private var persistedState: PersistedState {
        PersistedState(
            tasks: tasks,
            meetings: meetings,
            templates: templates,
            reviews: reviews,
            settings: settings,
            activeTaskID: nil,
            timerStartedAt: nil,
            timerAccumulatedSeconds: 0,
            focusSlots: focusSlots
        )
    }

    private func save() {
        _ = persist(persistedState)
    }

    private func persist(_ state: PersistedState) -> Bool {
        guard !persistenceBlocked else { return false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(state)
            try data.write(to: dataURL, options: .atomic)
            return true
        } catch {
            persistenceIssue = PersistenceIssue(
                title: "数据保存失败",
                message: "请检查磁盘空间或文件权限。错误：\(error.localizedDescription)"
            )
            return false
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

    private func scheduleEstimateReminder(for task: TaskItem, at now: Date? = nil) {
        let remaining = task.estimatedMinutes * 60 - elapsedSeconds(for: task, at: now)
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
        focusSlots = Array(repeating: nil, count: Self.defaultFocusSlotCount)
    }
}
