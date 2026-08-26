import Darwin
import Foundation

@main
@MainActor
struct AppStoreChecks {
    static func main() {
        var suite = CheckSuite()
        suite.run("切换任务保留双方用时", suite.checkTimerSwitching)
        suite.run("编辑活动任务重排提醒", suite.checkReminderRescheduling)
        suite.run("所有未完成任务都有看板入口", suite.checkBoardVisibility)
        suite.run("损坏数据先备份再恢复", suite.checkCorruptDataRecovery)
        suite.run("首次启动不注入演示活动", suite.checkCleanFirstLaunch)
        suite.run("偶数历史记录使用平均中位数", suite.checkEvenMedian)
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
        suite.run("自动工时按最晚减最早计算", suite.checkWorktimeSpanIncludesBreaks)
        suite.run("凌晨活动正确归入前一工作日", suite.checkWorktimeDayBoundary)
        suite.run("结束工时后停止自动更新", suite.checkClosedWorktimeIgnoresActivity)
        suite.run("工时轮询间隔不低于一分钟", suite.checkWorktimePollingMinimum)
        suite.run("自动采样与工时记录持久化", suite.checkWorktimeSamplingPersistence)
        suite.run("目标工时正确计算预计下班与进度", suite.checkWorktimeTargetCalculation)
        suite.run("预计下班提醒随目标更新并在结束后取消", suite.checkWorktimeTargetNotification)

        if suite.failureCount > 0 {
            print("FAILED: \(suite.failureCount) check(s)")
            exit(1)
        }
        print("PASSED: 23 checks")
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

    func checkTimerSwitching() throws {
        let context = try TestContext()
        defer { context.cleanUp() }

        context.store.addTask(title: "任务 A", category: "测试", estimatedMinutes: 30, date: context.clock.now)
        context.store.addTask(title: "任务 B", category: "测试", estimatedMinutes: 30, date: context.clock.now)
        let first = try require(context.store.tasks.first(where: { $0.title == "任务 A" }), "找不到任务 A")
        let second = try require(context.store.tasks.first(where: { $0.title == "任务 B" }), "找不到任务 B")

        context.store.startTask(first.id)
        context.clock.advance(seconds: 120)
        context.store.startTask(second.id)
        try expect(context.store.tasks.first(where: { $0.id == first.id })?.actualSeconds == 120, "任务 A 未保存 120 秒")

        context.clock.advance(seconds: 60)
        context.store.startTask(first.id)
        try expect(context.store.tasks.first(where: { $0.id == second.id })?.actualSeconds == 60, "任务 B 未保存 60 秒")
        try expect(context.store.elapsedSeconds() == 120, "返回任务 A 后累计时间不正确")
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

        let overdueIDs = Set(context.store.overdueTasks(referenceDate: context.clock.now).map(\.id))
        let otherIDs = Set(context.store.unplannedOrUpcomingTasks(referenceDate: context.clock.now).map(\.id))
        let todayIDs = Set(context.store.tasks(on: context.clock.now).filter { !$0.isCompleted }.map(\.id))
        let visibleIDs = overdueIDs.union(otherIDs).union(todayIDs)
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

        try expect(context.store.autoEstimate(title: "新分析", category: "分析").minutes == 30, "偶数中位数不是 30 分钟")
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

        try expect(context.store.moveTask(task.id, to: .yesterday, referenceDate: context.clock.now), "无法拖到昨天")
        var moved = try require(context.store.tasks.first(where: { $0.id == task.id }), "拖到昨天后任务消失")
        try expect(!moved.isCompleted, "拖到昨天后仍为已完成")
        try expect(Calendar.yiRi.isDate(moved.scheduledDate ?? .distantPast, inSameDayAs: context.clock.now.addingDays(-1)), "拖到昨天后日期不正确")

        try expect(context.store.moveTask(task.id, to: .todayPending, referenceDate: context.clock.now), "无法拖到今天待完成")
        moved = try require(context.store.tasks.first(where: { $0.id == task.id }), "拖到今天后任务消失")
        try expect(!moved.isCompleted, "拖到今天待完成后仍为已完成")
        try expect(Calendar.yiRi.isDate(moved.scheduledDate ?? .distantPast, inSameDayAs: context.clock.now), "拖到今天待完成后日期不正确")

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

    func sendFocusReminder(taskTitle: String) {}
    func scheduleEstimateReached(taskID: UUID, taskTitle: String, after seconds: Int) {
        scheduled.append(Scheduled(seconds: seconds))
    }
    func cancelEstimateReminder(taskID: UUID) {}
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
