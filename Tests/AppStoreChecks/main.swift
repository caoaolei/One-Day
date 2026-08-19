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
        suite.run("完成任务按日期分组并限制最近二十条", suite.checkCompletedGrouping)
        suite.run("完成与恢复立即更新看板分组", suite.checkCompleteAndRestore)
        suite.run("零计时任务显示为手动完成", suite.checkCompletionEffortText)

        if suite.failureCount > 0 {
            print("FAILED: \(suite.failureCount) check(s)")
            exit(1)
        }
        print("PASSED: 9 checks")
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
        try expect(earlier.count == 20, "更早完成没有限制为最近 20 条")
        try expect(context.store.earlierCompletedCount(referenceDate: context.clock.now) == 26, "更早完成总数被最近 20 条截断")
        try expect(earlier.first?.title == "更早 1", "更早完成没有按完成时间倒序")
        try expect(!earlier.contains(where: { $0.id == legacyTask.id }), "旧数据应在更早分组，但需排在有时间记录之后")

        let allEarlier = context.store.earlierCompleted(referenceDate: context.clock.now, limit: 30)
        try expect(allEarlier.last?.id == legacyTask.id, "缺少完成时间的旧数据没有归入更早完成")
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

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YiRiChecks-\(UUID().uuidString)", isDirectory: true)
        let dataURL = directory.appendingPathComponent("data.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let testClock = TestClock(now: Date(timeIntervalSince1970: 1_700_000_000))
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

private final class NotificationRecorder: TaskNotificationManaging, @unchecked Sendable {
    struct Scheduled { let seconds: Int }
    private(set) var scheduled: [Scheduled] = []

    func sendFocusReminder(taskTitle: String) {}
    func scheduleEstimateReached(taskID: UUID, taskTitle: String, after seconds: Int) {
        scheduled.append(Scheduled(seconds: seconds))
    }
    func cancelEstimateReminder(taskID: UUID) {}
}

private extension JSONDecoder {
    static var yiRi: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
