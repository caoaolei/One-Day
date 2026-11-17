import Darwin
import Foundation

@main
@MainActor
struct AppStoreChecks {
    static func main() {
        var suite = CheckSuite()
        suite.run("并行计时可独立暂停、释放与扩展槽位", suite.checkParallelTimers)
        suite.run("全部暂停保存各任务计时并保留槽位", suite.checkPauseAllFocusTasks)
        suite.run("今日任务拖放只在指定空槽启动有效待办", suite.checkStartingTodayTaskInSlot)
        suite.run("旧计时记录迁移并保留多个槽位", suite.checkFocusSlotMigration)
        suite.run("复盘释放计时槽位并保留未完成任务", suite.checkReviewStopsParallelTimers)
        suite.run("编辑活动任务重排提醒", suite.checkReminderRescheduling)
        suite.run("所有未完成任务都有看板入口", suite.checkBoardVisibility)
        suite.run("损坏数据先备份再恢复", suite.checkCorruptDataRecovery)
        suite.run("首次启动不注入演示活动", suite.checkCleanFirstLaunch)
        suite.run("偶数历史记录使用平均中位数", suite.checkEvenMedian)
        suite.run("估时优先匹配标题并排除未完成记录", suite.checkEstimateTitlePriority)
        suite.run("任务推荐结合历史用时、剩余用时和会议空档", suite.checkTaskRecommendation)
        suite.run("完成任务按今天与全部历史分组", suite.checkCompletedGrouping)
        suite.run("完成与恢复立即更新看板分组", suite.checkCompleteAndRestore)
        suite.run("零计时任务显示为手动完成", suite.checkCompletionEffortText)
        suite.run("拖放任务同步更新日期与完成状态", suite.checkBoardLaneMoves)
        suite.run("连续工作日计划正确跨过周末", suite.checkFutureWorkdayPlan)
        suite.run("未来任务按日期出现并跳过重复", suite.checkFutureTaskCreation)
        suite.run("成果档案按日汇总实际用时", suite.checkHistoryDaySummaries)
        suite.run("相似任务按名称而非分类归组", suite.checkAutomaticHistoryTopics)
        suite.run("人工事项整理持久化且不学习未来任务", suite.checkManualHistoryTopics)
        suite.run("完成复盘后当天封存且不可覆盖", suite.checkReviewFinalization)
        suite.run("完成复盘后自动工时继续记录", suite.checkReviewKeepsWorktimeRunning)
        suite.run("自动工时按最晚减最早计算", suite.checkWorktimeSpanIncludesBreaks)
        suite.run("凌晨活动正确归入前一工作日", suite.checkWorktimeDayBoundary)
        suite.run("结束工时后停止自动更新", suite.checkClosedWorktimeIgnoresActivity)
        suite.run("工时轮询间隔不低于一分钟", suite.checkWorktimePollingMinimum)
        suite.run("自动采样与工时记录持久化", suite.checkWorktimeSamplingPersistence)
        suite.run("目标工时正确计算预计下班与进度", suite.checkWorktimeTargetCalculation)
        suite.run("预计下班提醒随目标更新并在结束后取消", suite.checkWorktimeTargetNotification)
        suite.run("任务名称保留中间空格", suite.checkTaskTitleSpacing)
        suite.run("子任务独立完成并进入成果档案", suite.checkSubtaskLifecycle)
        suite.run("工时日历可补录并再次修正", suite.checkManualWorktimeBackfill)

        if suite.failureCount > 0 {
            print("FAILED: \(suite.failureCount) check(s)")
            exit(1)
        }
        print("PASSED: 33 checks")
    }
}

@MainActor
private struct CheckSuite {
    private(set) var failureCount = 0

    mutating func run(_ name: String, _ check: () throws -> Void) {
        do {
            try check()
            print("✓ \(name)")
        } catch {
            failureCount += 1
            print("✗ \(name): \(error)")
        }
    }

    func checkParallelTimers() throws {
        let context = try TestContext()
        defer { context.cleanUp() }
        let store = context.store
        let first = store.addTask(title: "任务 A", category: "测试", estimatedMinutes: 30, date: context.clock.now)
        let second = store.addTask(title: "任务 B", category: "测试", estimatedMinutes: 30, date: context.clock.now)
        let third = store.addTask(title: "任务 C", category: "测试", estimatedMinutes: 30, date: context.clock.now)
        try expect(store.focusSlots.count == 2, "默认未显示两个槽位")
        store.startTask(first.id, in: 1)
        context.clock.advance(seconds: 120)
        store.startTask(second.id)
        store.startTask(third.id)
        try expect(store.focusSlots[0]?.taskID == second.id && store.focusSlots[1]?.taskID == first.id, "满槽启动替换了原来的任务")
        context.clock.advance(seconds: 60)
        try expect(store.elapsedSeconds(for: first) == 180 && store.elapsedSeconds(for: second) == 60, "两个槽位未独立计时")

        store.pauseTask(first.id)
        context.clock.advance(seconds: 60)
        let paused = try require(store.tasks.first(where: { $0.id == first.id }), "暂停后丢失了任务")
        try expect(store.elapsedSeconds(for: paused) == 180 && store.elapsedSeconds(for: second) == 120, "暂停影响了另一项任务")
        try expect(context.notifications.cancelled == [first.id], "暂停取消了错误的提醒")

        store.addFocusSlot()
        store.startTask(third.id, in: 2)
        store.resumeTask(first.id)
        context.clock.advance(seconds: 60)
        store.stopTask(first.id)
        _ = store.moveTask(second.id, to: .todayCompleted)
        try expect(store.focusSlots[0] == nil && store.focusSlots[1] == nil, "移出或看板完成没有释放槽位")
        try expect(store.tasks.first(where: { $0.id == first.id && !$0.isCompleted })?.actualSeconds == 240, "移出任务没有保留已计时间")
        try expect(store.tasks.first(where: { $0.id == second.id && $0.isCompleted })?.actualSeconds == 180, "看板完成没有保留累计时间")
        try expect(store.elapsedSeconds(for: third) == 60, "槽位释放影响了其他计时")
        store.removeEmptyFocusSlot(1)
        try expect(store.focusSlots.count == 2 && store.focusSlot(for: third.id) == 1, "移除空槽后丢失运行中的任务")
        store.deleteTask(third.id)
        try expect(store.focusSlots.allSatisfy { $0 == nil }, "删除任务没有释放槽位")
    }

    func checkPauseAllFocusTasks() throws {
        let context = try TestContext()
        defer { context.cleanUp() }
        let store = context.store
        let today = context.clock.now
        let first = store.addTask(title: "先开始", category: "测试", estimatedMinutes: 30, date: today)
        let second = store.addTask(title: "后开始", category: "测试", estimatedMinutes: 30, date: today)
        let paused = store.addTask(title: "已经暂停", category: "测试", estimatedMinutes: 30, date: today)
        store.addFocusSlot()
        store.startTask(paused.id, in: 2)
        context.clock.advance(seconds: 30)
        store.pauseTask(paused.id)
        store.startTask(first.id, in: 0)
        context.clock.advance(seconds: 120)
        store.startTask(second.id, in: 1)
        context.clock.advance(seconds: 60)

        try expect(store.hasRunningFocusTasks, "未识别运行中的计时")
        store.pauseAllFocusTasks()
        try expect(!store.hasRunningFocusTasks, "仍有槽位正在计时")
        try expect(store.focusSlots.map { $0?.taskID } == [first.id, second.id, paused.id], "暂停改变了槽位归属")
        try expect(store.tasks.map(\.actualSeconds) == [180, 60, 30], "暂停时累计用时错误")
        try expect(store.tasks.allSatisfy { !$0.isCompleted }, "暂停时不应完成任务")
        try expect(context.notifications.cancelled == [paused.id, first.id, second.id], "未正确取消各任务的估时提醒")

        context.clock.advance(seconds: 90)
        store.pauseAllFocusTasks()
        let reopened = AppStore(
            dataURL: context.directory.appendingPathComponent("data.json"),
            notificationManager: context.notifications,
            nowProvider: { context.clock.now }
        )
        try expect(!reopened.hasRunningFocusTasks && reopened.tasks.map(\.actualSeconds) == [180, 60, 30], "重开后暂停状态或累计用时丢失")
        reopened.resumeTask(second.id)
        context.clock.advance(seconds: 30)
        let resumed = try require(reopened.tasks.first { $0.id == second.id }, "找不到继续计时的任务")
        try expect(reopened.elapsedSeconds(for: resumed) == 90, "继续后未从已累计的时间开始")
        try expect(reopened.focusSlots[0]?.startedAt == nil, "继续一项任务时重启了其他计时")
    }

    func checkStartingTodayTaskInSlot() throws {
        let context = try TestContext()
        defer { context.cleanUp() }
        let store = context.store
        let today = context.clock.now
        let first = store.addTask(title: "今日任务 A", category: "测试", estimatedMinutes: 30, date: today)
        let second = store.addTask(title: "今日任务 B", category: "测试", estimatedMinutes: 30, date: today)
        let future = store.addTask(title: "明日任务", category: "测试", estimatedMinutes: 30, date: today.addingDays(1))

        try expect(store.startTodayTask(first.id, in: 1), "应能拖到指定空槽位")
        try expect(store.focusSlots[1]?.startedAt == today && store.focusSlots[0] == nil, "未从所选槽位开始计时")
        try expect(!store.startTodayTask(second.id, in: 1), "不应替换已占用的槽位")
        try expect(!store.startTodayTask(first.id, in: 0), "同一个任务不应占多个槽位")
        try expect(!store.startTodayTask(future.id, in: 0), "不应开始明天的任务")
        store.setCompleted(second.id, completed: true)
        try expect(!store.startTodayTask(second.id, in: 0), "拖动中完成的任务不应再开始")
        try expect(store.focusSlots[1]?.taskID == first.id && store.focusSlots[0] == nil, "无效拖放改动了槽位")
    }

    func checkFocusSlotMigration() throws {
        let context = try TestContext()
        defer { context.cleanUp() }
        let now = context.clock.now
        let first = TaskItem(title: "旧计时", category: "测试", estimatedMinutes: 30, scheduledDate: now.startOfLocalDay)
        let second = TaskItem(title: "新计时", category: "测试", estimatedMinutes: 30, scheduledDate: now.startOfLocalDay)
        let state = PersistedState(
            tasks: [first, second], meetings: [], templates: [], reviews: [], settings: AppSettings(),
            activeTaskID: first.id, timerStartedAt: now.addingTimeInterval(-60), timerAccumulatedSeconds: 120
        )
        let dataURL = context.directory.appendingPathComponent("data.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: dataURL)
        let store = AppStore(dataURL: dataURL, notificationManager: context.notifications, nowProvider: { context.clock.now })
        let migrated = try require(store.tasks.first, "未读取旧任务")
        try expect(store.focusSlot(for: first.id) == 0 && store.elapsedSeconds(for: migrated) == 180, "旧活动计时迁移失败")
        store.addFocusSlot()
        store.startTask(second.id, in: 2)
        store.pauseTask(first.id)
        context.clock.advance(seconds: 60)

        let reopened = AppStore(dataURL: dataURL, notificationManager: context.notifications, nowProvider: { context.clock.now })
        let restored = try require(reopened.tasks.first, "重启后未读取任务")
        try expect(reopened.focusSlots.count == 3 && reopened.focusSlots[1] == nil, "重启后槽位数量或位置变化")
        try expect(reopened.focusSlots[0]?.startedAt == nil && reopened.elapsedSeconds(for: restored) == 180, "重启后暂停任务继续计时")
        try expect(reopened.focusSlot(for: second.id) == 2 && reopened.elapsedSeconds(for: second) == 60, "重启后运行中的任务未恢复")
    }

    func checkReviewStopsParallelTimers() throws {
        let context = try TestContext()
        defer { context.cleanUp() }
        let store = context.store
        let now = context.clock.now
        let first = store.addTask(title: "任务 A", category: "测试", estimatedMinutes: 30, date: now)
        let second = store.addTask(title: "任务 B", category: "测试", estimatedMinutes: 30, date: now)
        var settings = store.settings
        settings.carryOverPolicy = .tomorrow
        store.updateSettings(settings)
        store.startTask(first.id)
        store.startTask(second.id)
        context.clock.advance(seconds: 60)
        store.pauseTask(second.id)
        context.clock.advance(seconds: 60)

        let dataURL = context.directory.appendingPathComponent("data.json")
        let backupURL = context.directory.appendingPathComponent("saved-data.json")
        try FileManager.default.moveItem(at: dataURL, to: backupURL)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: false)
        try expect(!store.saveReview(note: "保存失败"), "写入失败仍返回成功")
        try expect(!store.isDayFinalized(now) && store.focusSlot(for: first.id) != nil, "写入失败仍封存当天或释放计时")
        try FileManager.default.removeItem(at: dataURL)
        try FileManager.default.moveItem(at: backupURL, to: dataURL)

        try expect(store.saveReview(note: "明天继续"), "复盘没有保存")
        let deferred = store.tasks(on: now.addingDays(1))
        try expect(store.focusSlots.allSatisfy { $0 == nil }, "封存后槽位仍被占用")
        try expect(deferred.count == 2 && deferred.allSatisfy { !$0.isCompleted }, "封存把尚未完成的任务标记为已完成")
        try expect(deferred.first(where: { $0.id == first.id })?.actualSeconds == 120, "复盘丢失了运行中的计时")
        try expect(deferred.first(where: { $0.id == second.id })?.actualSeconds == 60, "复盘丢失了暂停的计时")
    }

    func checkReminderRescheduling() throws {
        let context = try TestContext()
        defer { context.cleanUp() }

        context.store.addTask(title: "专注任务", category: "测试", estimatedMinutes: 30, date: context.clock.now)
        var task = try require(context.store.tasks.first, "找不到专注任务")
        context.store.startTask(task.id)
        context.clock.advance(seconds: 120)
        task.estimatedMinutes = 10
        context.store.updateTask(task)

        try expect(context.notifications.scheduled.last?.seconds == 8 * 60, "提醒没有按剩余 8 分钟重排")
    }

    func checkBoardVisibility() throws {
        let context = try TestContext()
        defer { context.cleanUp() }

        context.store.addTask(title: "待安排", category: "测试", estimatedMinutes: 10, date: nil)
        context.store.addTask(title: "未来", category: "测试", estimatedMinutes: 10, date: context.clock.now.addingDays(3))
        context.store.addTask(title: "逾期", category: "测试", estimatedMinutes: 10, date: context.clock.now.addingDays(-4))
        context.store.addTask(title: "今天", category: "测试", estimatedMinutes: 10, date: context.clock.now)

        let backlogIDs = Set(context.store.boardBacklogTasks(referenceDate: context.clock.now).map(\.id))
        let todayIDs = Set(context.store.tasks(on: context.clock.now).filter { !$0.isCompleted }.map(\.id))
        let visibleIDs = backlogIDs.union(todayIDs)
        try expect(visibleIDs == Set(context.store.tasks.map(\.id)), "仍有未完成任务没有看板入口")
    }

    func checkCorruptDataRecovery() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YiRiChecks-\(UUID().uuidString)", isDirectory: true)
        let dataURL = directory.appendingPathComponent("data.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: dataURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = AppStore(
            dataURL: dataURL,
            notificationManager: NotificationRecorder(),
            nowProvider: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        try expect(files.contains(where: { $0.hasPrefix("data-corrupt-") }), "没有生成损坏数据备份")
        try expect(store.persistenceIssue != nil, "没有向界面报告恢复提示")
        try expect(store.tasks.isEmpty, "恢复后不应注入演示任务")
        _ = try JSONDecoder.yiRi.decode(PersistedState.self, from: Data(contentsOf: dataURL))
    }

    func checkCleanFirstLaunch() throws {
        let context = try TestContext()
        defer { context.cleanUp() }

        try expect(context.store.tasks.isEmpty, "首次启动包含演示任务")
        try expect(context.store.meetings.isEmpty, "首次启动包含演示会议")
        try expect(context.store.templates.count == 2, "缺少内置模版")
    }

    func checkEvenMedian() throws {
        let context = try TestContext()
        defer { context.cleanUp() }

        context.store.addTask(title: "分析一", category: "分析", estimatedMinutes: 30, date: context.clock.now)
        context.store.addTask(title: "分析二", category: "分析", estimatedMinutes: 30, date: context.clock.now)
        var tasks = context.store.tasks
        tasks[0].actualSeconds = 20 * 60
        tasks[1].actualSeconds = 40 * 60
        context.store.updateTask(tasks[0])
        context.store.updateTask(tasks[1])
        context.store.setCompleted(tasks[0].id, completed: true)
        context.store.setCompleted(tasks[1].id, completed: true)

        try expect(context.store.autoEstimate(title: "新分析", category: "分析").minutes == 30, "偶数中位数不是 30 分钟")
    }

    func checkEstimateTitlePriority() throws {
        let context = try TestContext()
        defer { context.cleanUp() }
        let date = context.clock.now
        let exact = try addCompletedTask(to: context, title: "API 文档", completedAt: date, actualSeconds: 25 * 60)
        _ = try addCompletedTask(to: context, title: "API 文档 内部版", completedAt: date, actualSeconds: 35 * 60)
        _ = try addCompletedTask(to: context, title: "清理收件箱", completedAt: date, actualSeconds: 95 * 60, category: "写作")
        var unfinished = context.store.addTask(title: "ＡＰＩ－文档", category: "写作", estimatedMinutes: 30, date: date)
        unfinished.actualSeconds = 180 * 60
        context.store.updateTask(unfinished)

        let estimate = context.store.autoEstimate(title: unfinished.title, category: unfinished.category)
        try expect(estimate.minutes == 25 && estimate.reason.contains("同名"), "同名结果被未完成任务或分类样本干扰")
        let withoutSelf = context.store.autoEstimate(title: exact.title, category: "写作", excluding: exact.id)
        try expect(withoutSelf.minutes == 35 && withoutSelf.reason.contains("名称相似"), "编辑时使用了自身实际用时，或未优先参考相似名称")
    }

    func checkTaskRecommendation() throws {
        let start = try date(year: 2026, month: 11, day: 16, hour: 10)
        let context = try TestContext(now: start)
        defer { context.cleanUp() }
        let store = context.store
        _ = try addCompletedTask(to: context, title: "整理项目报表", completedAt: start.addingDays(-1), actualSeconds: 60 * 60)
        let longTask = store.addTask(title: "整理项目报表", category: "规划", estimatedMinutes: 15, date: start)
        let shortTask = store.addTask(title: "检查工单", category: "日常", estimatedMinutes: 20, date: start)
        _ = store.addTask(title: "明天准备方案", category: "写作", estimatedMinutes: 80, date: start.addingDays(1))

        if case .task(let task, let minutes, _, nil) = store.recommendNextTask(at: start) {
            try expect(task.id == longTask.id && minutes == 60, "没有用历史估时选出预计较长的今日待办")
        } else { throw CheckError("无会议时应推荐一项任务") }

        store.addMeeting(title: "评审", startDate: start.addingTimeInterval(30 * 60), durationMinutes: 20, location: "")
        if case .task(let task, let minutes, _, 25) = store.recommendNextTask(at: start) {
            try expect(task.id == shortTask.id && minutes == 20, "没有优先推荐能在会前完成的任务")
        } else { throw CheckError("未为会议留出 5 分钟准备时间") }

        var started = longTask
        started.actualSeconds = 35 * 60
        store.updateTask(started)
        if case .task(let task, 25, _, 25) = store.recommendNextTask(at: start) {
            try expect(task.id == longTask.id, "没有按剩余用时推荐已开始的任务")
        } else { throw CheckError("剩余用时计算错误") }

        if case .noTaskFits(availableMinutes: 5) = store.recommendNextTask(at: start.addingTimeInterval(20 * 60)) {} else {
            throw CheckError("空档太短时仍然推荐任务")
        }
        if case .meetingInProgress = store.recommendNextTask(at: start.addingTimeInterval(30 * 60)) {} else {
            throw CheckError("会议进行时仍然推荐任务")
        }
        store.startTask(shortTask.id)
        if case .task(let task, 25, _, 25) = store.recommendNextTask(at: start) {
            try expect(task.id == longTask.id, "有空槽位时没有推荐另一项待办")
        } else { throw CheckError("有空槽位时不应阻止推荐") }
        store.startTask(longTask.id)
        if case .focusSlotsFull = store.recommendNextTask(at: start) {} else {
            throw CheckError("槽位满时仍然推荐开启新的计时")
        }
    }

    func checkWorktimeSpanIncludesBreaks() throws {
        var ledger = WorktimeLedger()
        let settings = WorktimeSettings()
        let calendar = Calendar.yiRi
        let day = Date(timeIntervalSince1970: 1_700_000_000).startOfLocalDay
        let start = try require(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day), "无法构造上班时间")
        let end = try require(calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day), "无法构造下班时间")

        try expect(ledger.recordActivity(at: start, settings: settings), "未记录最早活动")
        try expect(ledger.recordActivity(at: end, settings: settings), "未记录最晚活动")
        let record = try require(ledger.record(on: day), "找不到工时记录")
        try expect(record.spanSeconds == 9 * 3600, "工时未按最晚减最早计算")
    }

    func checkWorktimeDayBoundary() throws {
        var ledger = WorktimeLedger()
        var settings = WorktimeSettings()
        settings.workdayBoundaryMinutes = 6 * 60
        let calendar = Calendar.yiRi
        let day = Date(timeIntervalSince1970: 1_700_000_000).startOfLocalDay
        let earlyMorning = try require(calendar.date(bySettingHour: 2, minute: 30, second: 0, of: day), "无法构造凌晨时间")

        _ = ledger.recordActivity(at: earlyMorning, settings: settings)
        try expect(ledger.record(on: day.addingDays(-1)) != nil, "凌晨活动未归入前一天")
        try expect(ledger.record(on: day) == nil, "凌晨活动误归入当天")
    }

    func checkClosedWorktimeIgnoresActivity() throws {
        var ledger = WorktimeLedger()
        let settings = WorktimeSettings()
        let day = Date(timeIntervalSince1970: 1_700_000_000).startOfLocalDay
        let start = day.addingTimeInterval(9 * 3600)
        let end = day.addingTimeInterval(18 * 3600)
        _ = ledger.recordActivity(at: start, settings: settings)
        try expect(ledger.closeWorkday(containing: end, at: end, settings: settings), "结束工时失败")
        try expect(!ledger.recordActivity(at: end.addingTimeInterval(3600), settings: settings), "结束后仍自动更新")
        let closed = try require(ledger.record(on: day), "找不到已结束记录")
        try expect(closed.effectiveEndAt == end, "结束时间被后续活动覆盖")

        try expect(ledger.resumeWorkday(containing: end, settings: settings), "恢复工时失败")
        try expect(ledger.recordActivity(at: end.addingTimeInterval(3600), settings: settings), "恢复后未继续记录")
    }

    func checkWorktimePollingMinimum() throws {
        var settings = WorktimeSettings()
        settings.pollingMinutes = 0
        try expect(settings.normalized.pollingMinutes == 1, "轮询间隔可以低于一分钟")
    }

    func checkWorktimeSamplingPersistence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YiRiWorktimeChecks-\(UUID().uuidString)", isDirectory: true)
        let dataURL = directory.appendingPathComponent("worktime.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let calendar = Calendar.yiRi
        let day = Date(timeIntervalSince1970: 1_700_000_000).startOfLocalDay
        let clock = TestClock(now: try require(calendar.date(bySettingHour: 9, minute: 0, second: 30, of: day), "无法构造采样时间"))
        let idleProvider = MutableIdleProvider()
        let controller = WorktimeController(
            dataURL: dataURL,
            idleProvider: idleProvider,
            nowProvider: { clock.now },
            startsMonitoring: false
        )
        var settings = controller.settings
        settings.isEnabled = true
        controller.updateSettings(settings)

        idleProvider.value = 30
        controller.sampleNow()
        clock.now = try require(calendar.date(bySettingHour: 18, minute: 0, second: 20, of: day), "无法构造第二次采样时间")
        idleProvider.value = 20
        controller.sampleNow()

        let sampled = try require(controller.record(on: clock.now), "自动采样未创建工时记录")
        try expect(sampled.spanSeconds == 9 * 3600, "自动采样时间计算不正确")

        let reloaded = WorktimeController(
            dataURL: dataURL,
            idleProvider: idleProvider,
            nowProvider: { clock.now },
            startsMonitoring: false
        )
        try expect(reloaded.record(on: clock.now)?.spanSeconds == 9 * 3600, "工时记录没有持久化")
        try expect(reloaded.settings.isEnabled, "工时设置没有持久化")
    }

    func checkWorktimeTargetCalculation() throws {
        let day = Date(timeIntervalSince1970: 1_700_000_000).startOfLocalDay
        let start = day.addingTimeInterval(9 * 3600)
        let record = DailyWorktimeRecord(
            workDate: day,
            firstActivityAt: start,
            lastActivityAt: start.addingTimeInterval(4 * 3600)
        )
        try expect(record.expectedEndAt(targetMinutes: 8 * 60) == start.addingTimeInterval(8 * 3600), "预计下班时间不正确")
        try expect(record.goalProgress(targetMinutes: 8 * 60) == 0.5, "目标工时进度不正确")
    }

    func checkWorktimeTargetNotification() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YiRiWorktimeTargetChecks-\(UUID().uuidString)", isDirectory: true)
        let dataURL = directory.appendingPathComponent("worktime.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let day = Date(timeIntervalSince1970: 1_700_000_000).startOfLocalDay
        let clock = TestClock(now: day.addingTimeInterval(9 * 3600 + 30))
        let idleProvider = MutableIdleProvider()
        idleProvider.value = 30
        let notifications = WorktimeNotificationRecorder()
        let controller = WorktimeController(
            dataURL: dataURL,
            idleProvider: idleProvider,
            notificationManager: notifications,
            nowProvider: { clock.now },
            startsMonitoring: false
        )
        var settings = controller.settings
        settings.isEnabled = true
        controller.updateSettings(settings)

        let initial = try require(notifications.scheduled.last, "首次活动没有安排预计下班提醒")
        try expect(initial.startAt == day.addingTimeInterval(9 * 3600), "提醒使用的上班时间不正确")
        try expect(initial.expectedEndAt == day.addingTimeInterval(17 * 3600), "8 小时目标的预计下班时间不正确")

        settings.dailyTargetMinutes = 7 * 60 + 30
        controller.updateSettings(settings)
        try expect(notifications.scheduled.last?.expectedEndAt == day.addingTimeInterval(16 * 3600 + 30 * 60), "修改目标后提醒没有重排")

        try expect(controller.endToday(at: day.addingTimeInterval(18 * 3600)), "无法结束今日工时")
        try expect(notifications.cancelled.contains(where: { Calendar.yiRi.isDate($0, inSameDayAs: day) }), "结束工时后没有取消提醒")
    }

    func checkCompletedGrouping() throws {
        let context = try TestContext()
        defer { context.cleanUp() }

        context.store.addTask(title: "逾期但今天完成", category: "测试", estimatedMinutes: 10, date: context.clock.now.addingDays(-3))
        let todayTask = try require(context.store.tasks.first, "找不到今日完成任务")
        context.store.setCompleted(todayTask.id, completed: true)

        context.store.addTask(title: "旧数据", category: "测试", estimatedMinutes: 10, date: context.clock.now.addingDays(-8))
        var legacyTask = try require(context.store.tasks.first(where: { $0.title == "旧数据" }), "找不到旧数据任务")
        legacyTask.isCompleted = true
        legacyTask.completedAt = nil
        context.store.updateTask(legacyTask)

        for day in 1...25 {
            context.store.addTask(title: "更早 \(day)", category: "测试", estimatedMinutes: 10, date: context.clock.now.addingDays(-day))
            var task = try require(context.store.tasks.first(where: { $0.title == "更早 \(day)" }), "找不到更早完成任务")
            task.isCompleted = true
            task.completedAt = context.clock.now.addingDays(-day).addingTimeInterval(TimeInterval(day))
            context.store.updateTask(task)
        }

        let completedToday = context.store.completedToday(referenceDate: context.clock.now)
        let earlier = context.store.earlierCompleted(referenceDate: context.clock.now)
        try expect(completedToday.map(\.id) == [todayTask.id], "逾期任务今天完成后没有计入今日成果")
        try expect(earlier.count == 26, "历史完成列表没有包含全部记录")
        try expect(context.store.earlierCompletedCount(referenceDate: context.clock.now) == 26, "更早完成总数被最近 20 条截断")
        try expect(earlier.first?.title == "更早 1", "更早完成没有按完成时间倒序")
        try expect(earlier.last?.id == legacyTask.id, "缺少完成时间的旧数据没有归入历史完成")
    }

    func checkCompleteAndRestore() throws {
        let context = try TestContext()
        defer { context.cleanUp() }

        context.store.addTask(title: "可恢复任务", category: "测试", estimatedMinutes: 10, date: context.clock.now)
        let task = try require(context.store.tasks.first, "找不到可恢复任务")
        context.store.setCompleted(task.id, completed: true)

        try expect(context.store.tasks(on: context.clock.now).filter { !$0.isCompleted }.isEmpty, "完成后仍留在今天待办")
        try expect(context.store.completedToday(referenceDate: context.clock.now).count == 1, "完成后今日成果数量没有更新")

        context.store.setCompleted(task.id, completed: false)
        try expect(context.store.tasks(on: context.clock.now).filter { !$0.isCompleted }.map(\.id) == [task.id], "恢复后没有回到今天待办")
        try expect(context.store.completedToday(referenceDate: context.clock.now).isEmpty, "恢复后今日成果数量没有更新")
    }

    func checkCompletionEffortText() throws {
        var task = TaskItem(title: "手动完成", category: "测试", estimatedMinutes: 10)
        try expect(task.completionEffortText == "手动完成", "零计时显示了误导性的 0 分钟")
        task.actualSeconds = 120
        try expect(task.completionEffortText == "专注 2 分钟", "实际专注用时文案不正确")
    }

    func checkBoardLaneMoves() throws {
        let context = try TestContext()
        defer { context.cleanUp() }

        context.store.addTask(title: "拖放任务", category: "测试", estimatedMinutes: 10, date: context.clock.now.addingDays(3))
        let task = try require(context.store.tasks.first, "找不到拖放任务")

        try expect(!context.store.moveTask(task.id, to: .backlog, referenceDate: context.clock.now), "未来任务已在待安排列时不应重复修改")

        try expect(context.store.moveTask(task.id, to: .todayPending, referenceDate: context.clock.now), "无法拖到今天待完成")
        var moved = try require(context.store.tasks.first(where: { $0.id == task.id }), "拖到今天后任务消失")
        try expect(!moved.isCompleted, "拖到今天待完成后仍为已完成")
        try expect(Calendar.yiRi.isDate(moved.scheduledDate ?? .distantPast, inSameDayAs: context.clock.now), "拖到今天待完成后日期不正确")

        try expect(context.store.moveTask(task.id, to: .backlog, referenceDate: context.clock.now), "无法拖到待安排")
        moved = try require(context.store.tasks.first(where: { $0.id == task.id }), "拖到待安排后任务消失")
        try expect(!moved.isCompleted && moved.scheduledDate == nil, "拖到待安排后没有清除安排日期")

        try expect(context.store.moveTask(task.id, to: .todayPending, referenceDate: context.clock.now), "无法从待安排拖回今天")

        try expect(context.store.moveTask(task.id, to: .todayCompleted, referenceDate: context.clock.now), "无法拖到今天已完成")
        moved = try require(context.store.tasks.first(where: { $0.id == task.id }), "拖到已完成后任务消失")
        try expect(moved.isCompleted, "拖到今天已完成后状态未更新")
        try expect(Calendar.yiRi.isDate(moved.completedAt ?? .distantPast, inSameDayAs: context.clock.now), "拖到今天已完成后完成时间不正确")

        context.clock.advance(seconds: 60)
        try expect(!context.store.moveTask(task.id, to: .todayCompleted, referenceDate: context.clock.now), "拖回同一列不应重复修改")
        let unchanged = try require(context.store.tasks.first(where: { $0.id == task.id }), "重复拖放后任务消失")
        try expect(unchanged.completedAt == moved.completedAt, "拖回同一列改写了完成时间")

        try expect(context.store.moveTask(task.id, to: .todayPending, referenceDate: context.clock.now), "已完成任务无法拖回今天待完成")
        let restored = try require(context.store.tasks.first(where: { $0.id == task.id }), "恢复后任务消失")
        try expect(!restored.isCompleted && restored.completedAt == nil, "拖回待完成后没有清除完成状态")
    }

    func checkFutureWorkdayPlan() throws {
        let friday = try date(year: 2026, month: 8, day: 21, hour: 9)
        let context = try TestContext(now: friday)
        defer { context.cleanUp() }

        let plan = context.store.futureWorkdayPlan(
            title: "连续任务",
            workdayCount: 5,
            skipDuplicates: false,
            referenceDate: friday
        )
        try expect(plan.dates.count == 5, "没有生成 5 个工作日")
        try expect(dayComponents(plan.dates.first) == DateComponents(year: 2026, month: 8, day: 24), "周五后的首个工作日不是周一")
        try expect(dayComponents(plan.dates.last) == DateComponents(year: 2026, month: 8, day: 28), "5 个工作日的末日不正确")
        try expect(plan.dates.allSatisfy { (2...6).contains(Calendar.yiRi.component(.weekday, from: $0)) }, "连续计划包含周末")
    }

    func checkFutureTaskCreation() throws {
        let friday = try date(year: 2026, month: 8, day: 21, hour: 9)
        let context = try TestContext(now: friday)
        defer { context.cleanUp() }

        let firstResult = context.store.addFutureWorkdayTasks(
            title: "连续任务",
            category: "测试",
            estimatedMinutes: 30,
            workdayCount: 1,
            skipDuplicates: true,
            referenceDate: friday
        )
        let monday = try date(year: 2026, month: 8, day: 24)
        try expect(firstResult.createdCount == 1, "单个未来工作日任务创建失败")
        try expect(context.store.tasks(on: friday).isEmpty, "未来任务提前进入今日待办")
        try expect(context.store.tasks(on: monday).map(\.title) == ["连续任务"], "目标日期没有自动出现未来任务")

        let preview = context.store.futureWorkdayPlan(
            title: "连续任务",
            workdayCount: 92,
            skipDuplicates: true,
            referenceDate: friday
        )
        try expect(preview.dates.count == 92, "92 个工作日边界被截断")
        try expect(preview.creatableDates.count == 91 && preview.skippedDuplicateCount == 1, "同日同名任务没有被跳过")

        let result = context.store.addFutureWorkdayTasks(
            title: "连续任务",
            category: "测试",
            estimatedMinutes: 30,
            workdayCount: 92,
            skipDuplicates: true,
            referenceDate: friday
        )
        try expect(result.createdCount == 91 && context.store.tasks.count == 92, "批量创建或去重数量不正确")
    }

    func checkHistoryDaySummaries() throws {
        let context = try TestContext()
        defer { context.cleanUp() }

        let timed = try addCompletedTask(to: context, title: "今日计时", completedAt: context.clock.now, actualSeconds: 120)
        _ = try addCompletedTask(to: context, title: "今日手动", completedAt: context.clock.now.addingTimeInterval(-60), actualSeconds: 0)
        _ = try addCompletedTask(to: context, title: "昨日计时", completedAt: context.clock.now.addingDays(-1), actualSeconds: 60)
        _ = try addCompletedTask(to: context, title: "旧记录", completedAt: nil, actualSeconds: 0)

        let groups = context.store.completedDayGroups()
        try expect(groups.count == 3, "日期分组数量不正确")
        try expect(groups.first?.tasks.contains(where: { $0.id == timed.id }) == true, "今天没有排在日期视图顶部")
        try expect(groups.first?.totalActualSeconds == 120, "每日实际专注时长汇总不正确")
        try expect(groups.first?.manualCompletionCount == 1, "每日手动完成数量不正确")
        try expect(groups.last?.day == nil && groups.last?.tasks.first?.title == "旧记录", "缺少完成时间的任务没有归入较早记录")
    }

    func checkAutomaticHistoryTopics() throws {
        let context = try TestContext()
        defer { context.cleanUp() }

        let volumeOne = try addCompletedTask(to: context, title: "音量-SID 探索", completedAt: context.clock.now, actualSeconds: 60, category: "深度工作")
        let volumeTwo = try addCompletedTask(to: context, title: "音量：环境音训练", completedAt: context.clock.now.addingTimeInterval(-60), actualSeconds: 120, category: "研究")
        let report = try addCompletedTask(to: context, title: "撰写项目报告", completedAt: context.clock.now.addingTimeInterval(-120), actualSeconds: 180, category: "深度工作")
        let email = try addCompletedTask(to: context, title: "清理收件箱", completedAt: context.clock.now.addingTimeInterval(-180), actualSeconds: 60, category: "深度工作")

        let topics = context.store.historyTopics()
        let volumeTopic = try require(topics.first(where: { topic in
            let ids = Set(topic.tasks.map(\.id))
            return ids.contains(volumeOne.id) && ids.contains(volumeTwo.id)
        }), "相似的音量任务没有归入同一事项")
        try expect(volumeTopic.tasks.count == 2, "相似事项混入了无关任务")
        try expect(!topics.contains(where: { topic in
            let ids = Set(topic.tasks.map(\.id))
            return ids.contains(report.id) && ids.contains(email.id)
        }), "仅分类相同的任务被错误归组")
    }

    func checkManualHistoryTopics() throws {
        let context = try TestContext()
        defer { context.cleanUp() }

        let first = try addCompletedTask(to: context, title: "音量-SID", completedAt: context.clock.now, actualSeconds: 60)
        let second = try addCompletedTask(to: context, title: "音量-环境音", completedAt: context.clock.now.addingTimeInterval(-60), actualSeconds: 120)
        let automatic = try require(context.store.historyTopics().first(where: { $0.tasks.count == 2 }), "初始相似事项不存在")
        context.store.renameHistoryTopic(automatic, to: "音量项目")

        let third = try addCompletedTask(to: context, title: "音量-响度", completedAt: context.clock.now.addingTimeInterval(60), actualSeconds: 180)
        var topics = context.store.historyTopics()
        let confirmed = try require(topics.first(where: { $0.name == "音量项目" }), "人工事项名称没有保存")
        try expect(Set(confirmed.tasks.map(\.id)) == Set([first.id, second.id]), "新任务错误沿用了人工修正")
        let newAutomatic = try require(topics.first(where: { $0.tasks.contains(where: { $0.id == third.id }) }), "未来相似任务没有保留自动分组")

        context.store.moveHistoryTask(third.id, to: confirmed)
        topics = context.store.historyTopics()
        let mergedByMove = try require(topics.first(where: { $0.name == "音量项目" }), "移动记录后目标事项消失")
        try expect(mergedByMove.tasks.count == 3, "移入其他事项失败")

        context.store.splitHistoryTask(third.id, newTopicName: "响度专项")
        topics = context.store.historyTopics()
        let split = try require(topics.first(where: { $0.name == "响度专项" }), "拆成新事项失败")
        let remaining = try require(topics.first(where: { $0.name == "音量项目" }), "拆分后原事项消失")
        context.store.mergeHistoryTopic(split, into: remaining)
        try expect(context.store.historyTopics().first(where: { $0.name == "音量项目" })?.tasks.count == 3, "合并事项失败")

        let reloaded = AppStore(
            dataURL: context.directory.appendingPathComponent("data.json"),
            notificationManager: NotificationRecorder(),
            nowProvider: { context.clock.now }
        )
        try expect(reloaded.historyTopics().first(where: { $0.name == "音量项目" })?.tasks.count == 3, "人工事项整理没有持久化")
        try expect(newAutomatic.manualGroupID == nil, "自动事项被提前物化")

        let encoded = try JSONEncoder().encode(TaskItem(title: "兼容旧数据", category: "测试", estimatedMinutes: 10))
        let decoded = try JSONDecoder().decode(TaskItem.self, from: encoded)
        try expect(decoded.historyGroupID == nil && decoded.historyGroupName == nil, "缺少新字段的任务无法兼容")
    }

    func checkReviewFinalization() throws {
        let context = try TestContext()
        defer { context.cleanUp() }

        context.store.addTask(title: "封存测试", category: "测试", estimatedMinutes: 20, date: context.clock.now)
        try expect(context.store.saveReview(note: "第一版复盘"), "首次完成复盘失败")
        try expect(context.store.isDayFinalized(context.clock.now), "完成复盘后当天没有进入封存状态")
        try expect(context.store.tasks.count == 1, "封存当天错误删除了任务数据")

        try expect(!context.store.saveReview(note: "不应覆盖"), "已封存复盘仍可再次保存")
        try expect(context.store.review(on: context.clock.now)?.note == "第一版复盘", "已封存复盘被覆盖")

        context.clock.advance(seconds: 24 * 60 * 60)
        try expect(!context.store.isDayFinalized(context.clock.now), "新的一天仍被错误锁定")
        try expect(context.store.saveReview(note: "第二天复盘"), "新的一天无法完成复盘")
    }

    func checkReviewKeepsWorktimeRunning() throws {
        let context = try TestContext()
        defer { context.cleanUp() }

        let idleProvider = MutableIdleProvider()
        idleProvider.value = 0
        let controller = WorktimeController(
            dataURL: context.directory.appendingPathComponent("worktime.json"),
            idleProvider: idleProvider,
            nowProvider: { context.clock.now },
            startsMonitoring: false
        )
        var settings = controller.settings
        settings.isEnabled = true
        controller.updateSettings(settings)
        try expect(controller.record(on: context.clock.now) != nil, "复盘前没有创建工时记录")

        try expect(context.store.saveReview(note: "任务复盘已完成"), "无法完成复盘")
        context.clock.advance(seconds: 60 * 60)
        controller.sampleNow()

        let record = try require(controller.record(on: context.clock.now), "复盘后工时记录消失")
        try expect(!record.isClosed, "完成复盘错误结束了自动工时")
        try expect(record.spanSeconds == 60 * 60, "完成复盘后自动工时没有继续更新")
    }

    func checkTaskTitleSpacing() throws {
        let context = try TestContext()
        defer { context.cleanUp() }

        let task = context.store.addTask(
            title: "整理 项目 方案",
            category: "测试",
            estimatedMinutes: 30,
            date: context.clock.now
        )
        try expect(task.title == "整理 项目 方案", "创建任务时丢失了中间空格")

        let reloaded = AppStore(
            dataURL: context.directory.appendingPathComponent("data.json"),
            notificationManager: NotificationRecorder(),
            nowProvider: { context.clock.now }
        )
        try expect(reloaded.tasks.first?.title == "整理 项目 方案", "持久化后丢失了任务名空格")
    }

    func checkSubtaskLifecycle() throws {
        let context = try TestContext()
        defer { context.cleanUp() }

        let parent = context.store.addTaskWithSubtasks(
            title: "发布产品说明",
            category: "写作",
            estimatedMinutes: 60,
            date: context.clock.now,
            subtasks: [
                TaskSubtaskDraft(title: "补充 功能截图", estimatedMinutes: 20),
                TaskSubtaskDraft(title: "检查更新日志", estimatedMinutes: 15)
            ]
        )
        let children = context.store.subtasks(of: parent)
        try expect(children.count == 2, "没有一次创建全部子任务")
        try expect(children.allSatisfy { $0.parentTaskID == parent.id }, "子任务没有关联父任务")
        try expect(children.allSatisfy {
            Calendar.yiRi.isDate($0.scheduledDate ?? .distantPast, inSameDayAs: context.clock.now)
        }, "子任务没有继承父任务日期")

        let completedChild = try require(children.first, "找不到要完成的子任务")
        context.store.setCompleted(completedChild.id, completed: true)
        try expect(context.store.completedTasks().contains(where: { $0.id == completedChild.id }), "子任务没有进入成果档案")

        let reloaded = AppStore(
            dataURL: context.directory.appendingPathComponent("data.json"),
            notificationManager: NotificationRecorder(),
            nowProvider: { context.clock.now }
        )
        try expect(reloaded.tasks.first(where: { $0.id == completedChild.id })?.parentTaskID == parent.id, "父子关系没有持久化")

        let futureResult = context.store.addFutureWorkdayTasks(
            title: "连续主任务",
            category: "规划",
            estimatedMinutes: 30,
            workdayCount: 1,
            skipDuplicates: true,
            subtasks: [TaskSubtaskDraft(title: "连续子任务", estimatedMinutes: 10)],
            referenceDate: context.clock.now
        )
        try expect(futureResult.createdCount == 1, "带子任务的未来计划没有创建主任务")
        let futureParent = try require(context.store.tasks.first(where: { $0.title == "连续主任务" }), "找不到未来主任务")
        let futureChild = try require(context.store.tasks.first(where: { $0.title == "连续子任务" }), "找不到未来子任务")
        try expect(futureChild.parentTaskID == futureParent.id, "未来计划中的子任务关联错误")
        try expect(futureChild.scheduledDate == futureParent.scheduledDate, "未来子任务没有继承主任务日期")

        context.store.deleteTask(parent.id)
        try expect(context.store.tasks.contains(where: { $0.id == completedChild.id }), "删除父任务时错误删除了子任务")
        try expect(context.store.tasks.first(where: { $0.id == completedChild.id })?.parentTaskID == nil, "删除父任务后留下了失效关联")
    }

    func checkManualWorktimeBackfill() throws {
        var ledger = WorktimeLedger()
        let day = Date(timeIntervalSince1970: 1_700_000_000).startOfLocalDay
        let start = day.addingTimeInterval(9 * 3600 + 30 * 60)
        let end = day.addingTimeInterval(18 * 3600 + 30 * 60)

        try expect(ledger.setManualRecord(on: day, startAt: start, endAt: end), "无法为无记录日期补录工时")
        var record = try require(ledger.record(on: day), "补录后没有生成日期记录")
        try expect(record.isManuallyAdjusted && record.isClosed, "补录记录没有标记为手动且已结束")
        try expect(record.spanSeconds == 9 * 3600, "补录工时没有按下班减上班计算")

        let correctedEnd = day.addingTimeInterval(19 * 3600)
        try expect(ledger.setManualRecord(on: day, startAt: start, endAt: correctedEnd), "无法再次修正补录工时")
        record = try require(ledger.record(on: day), "修正后记录消失")
        try expect(ledger.records.count == 1, "再次修正时重复创建了日期记录")
        try expect(record.spanSeconds == 9 * 3600 + 30 * 60, "再次修正的工时不正确")
    }

    private func addCompletedTask(
        to context: TestContext,
        title: String,
        completedAt: Date?,
        actualSeconds: Int,
        category: String = "测试"
    ) throws -> TaskItem {
        context.store.addTask(title: title, category: category, estimatedMinutes: 10, date: completedAt ?? context.clock.now)
        var task = try require(context.store.tasks.last, "创建完成任务失败")
        task.isCompleted = true
        task.completedAt = completedAt
        task.actualSeconds = actualSeconds
        context.store.updateTask(task)
        return task
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 12) throws -> Date {
        try require(
            Calendar.yiRi.date(from: DateComponents(year: year, month: month, day: day, hour: hour)),
            "无法构造测试日期"
        )
    }

    private func dayComponents(_ date: Date?) -> DateComponents {
        guard let date else { return DateComponents() }
        return Calendar.yiRi.dateComponents([.year, .month, .day], from: date)
    }

    private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw CheckError(message) }
    }

    private func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw CheckError(message) }
        return value
    }
}

private struct CheckError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@MainActor
private final class TestContext {
    let directory: URL
    let clock: TestClock
    let notifications: NotificationRecorder
    let store: AppStore

    init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YiRiChecks-\(UUID().uuidString)", isDirectory: true)
        let dataURL = directory.appendingPathComponent("data.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let testClock = TestClock(now: now)
        let recorder = NotificationRecorder()
        clock = testClock
        notifications = recorder
        store = AppStore(
            dataURL: dataURL,
            notificationManager: recorder,
            nowProvider: { testClock.now }
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class TestClock {
    var now: Date
    init(now: Date) { self.now = now }
    func advance(seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

private final class MutableIdleProvider: UserIdleTimeProviding {
    var value: TimeInterval?

    func idleSeconds() -> TimeInterval? {
        value
    }
}

private final class NotificationRecorder: TaskNotificationManaging, @unchecked Sendable {
    struct Scheduled { let seconds: Int }
    private(set) var scheduled: [Scheduled] = []
    private(set) var cancelled: [UUID] = []

    func sendFocusReminder(taskTitle: String) {}
    func scheduleEstimateReached(taskID: UUID, taskTitle: String, after seconds: Int) {
        scheduled.append(Scheduled(seconds: seconds))
    }
    func cancelEstimateReminder(taskID: UUID) { cancelled.append(taskID) }
}

private final class WorktimeNotificationRecorder: WorktimeNotificationManaging, @unchecked Sendable {
    struct Scheduled {
        let workDate: Date
        let startAt: Date
        let expectedEndAt: Date
        let targetMinutes: Int
    }

    private(set) var scheduled: [Scheduled] = []
    private(set) var cancelled: [Date] = []

    func scheduleWorktimeTarget(
        workDate: Date,
        startAt: Date,
        expectedEndAt: Date,
        targetMinutes: Int
    ) {
        scheduled.append(Scheduled(
            workDate: workDate,
            startAt: startAt,
            expectedEndAt: expectedEndAt,
            targetMinutes: targetMinutes
        ))
    }

    func cancelWorktimeTarget(workDate: Date) {
        cancelled.append(workDate)
    }
}

private extension JSONDecoder {
    static var yiRi: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
