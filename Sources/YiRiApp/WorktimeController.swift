import AppKit
import CoreGraphics
import Foundation
import ServiceManagement
import SwiftUI

protocol UserIdleTimeProviding {
    func idleSeconds() -> TimeInterval?
}

struct SystemUserIdleTimeProvider: UserIdleTimeProviding {
    func idleSeconds() -> TimeInterval? {
        guard let anyInputEvent = CGEventType(rawValue: UInt32.max) else { return nil }
        let value = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: anyInputEvent
        )
        guard value.isFinite, value >= 0 else { return nil }
        return value
    }
}

@MainActor
final class WorktimeController: ObservableObject {
    @Published private(set) var records: [DailyWorktimeRecord] = []
    @Published private(set) var settings = WorktimeSettings()
    @Published private(set) var currentIdleSeconds: TimeInterval?
    @Published private(set) var sensorAvailable = true
    @Published private(set) var persistenceMessage: String?
    @Published private(set) var launchAtLoginMessage: String?

    private let dataURL: URL
    private let idleProvider: any UserIdleTimeProviding
    private let notificationManager: any WorktimeNotificationManaging
    private let nowProvider: () -> Date
    private var ledger = WorktimeLedger()
    private var monitoringTask: Task<Void, Never>?
    private var persistenceBlocked = false

    init(
        dataURL: URL? = nil,
        idleProvider: any UserIdleTimeProviding = SystemUserIdleTimeProvider(),
        notificationManager: any WorktimeNotificationManaging = NotificationManager.shared,
        nowProvider: @escaping () -> Date = Date.init,
        startsMonitoring: Bool = true
    ) {
        let fileManager = FileManager.default
        if let dataURL {
            self.dataURL = dataURL
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.dataURL = support
                .appendingPathComponent("YiRi", isDirectory: true)
                .appendingPathComponent("worktime.json")
        }
        self.idleProvider = idleProvider
        self.notificationManager = notificationManager
        self.nowProvider = nowProvider

        do {
            try fileManager.createDirectory(
                at: self.dataURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            persistenceBlocked = true
            persistenceMessage = "无法创建工时数据目录：\(error.localizedDescription)"
        }

        load()
        refreshTargetNotification()
        if startsMonitoring {
            startMonitoring()
        }
    }

    var sortedRecords: [DailyWorktimeRecord] {
        records.sorted { $0.workDate > $1.workDate }
    }

    func record(on date: Date) -> DailyWorktimeRecord? {
        let workDate = WorktimeLedger.workDate(for: date, boundaryMinutes: settings.workdayBoundaryMinutes)
        return ledger.record(on: workDate)
    }

    func status(at date: Date = Date()) -> WorktimeDisplayStatus {
        guard settings.isEnabled else { return .disabled }
        guard sensorAvailable else { return .unavailable }
        guard let record = record(on: date) else { return .waiting }
        if record.isClosed { return .ended }
        let freshness = TimeInterval(settings.pollingMinutes * 60 + 10)
        if let currentIdleSeconds, currentIdleSeconds > freshness { return .away }
        return .recording
    }

    func updateSettings(_ newSettings: WorktimeSettings) {
        let oldInterval = settings.pollingMinutes
        let wasEnabled = settings.isEnabled
        let oldTarget = settings.dailyTargetMinutes
        settings = newSettings.normalized
        save()
        if oldInterval != settings.pollingMinutes {
            restartMonitoring()
        }
        if settings.isEnabled, !wasEnabled {
            sampleNow()
        }
        if !settings.isEnabled {
            cancelTargetNotification()
        } else if !wasEnabled || oldTarget != settings.dailyTargetMinutes {
            refreshTargetNotification()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        var next = settings
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
                launchAtLoginMessage = "已设置登录后自动启动"
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
                launchAtLoginMessage = "已关闭登录后自动启动"
            }
            next.launchAtLogin = enabled
        } catch {
            next.launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginMessage = "登录项设置失败：\(error.localizedDescription)"
        }
        settings = next.normalized
        save()
    }

    func sampleNow() {
        guard settings.isEnabled else {
            currentIdleSeconds = nil
            return
        }
        let now = nowProvider()
        guard let idle = idleProvider.idleSeconds(), idle.isFinite, idle >= 0 else {
            sensorAvailable = false
            return
        }

        sensorAvailable = true
        currentIdleSeconds = idle
        let freshness = TimeInterval(settings.pollingMinutes * 60 + 10)
        guard idle <= freshness else { return }

        let activityAt = now.addingTimeInterval(-idle)
        let wasUnrecorded = record(on: activityAt) == nil
        if ledger.recordActivity(at: activityAt, settings: settings) {
            publishAndSave()
            if wasUnrecorded {
                refreshTargetNotification(at: activityAt)
            }
        }
    }

    @discardableResult
    func endToday(at date: Date? = nil) -> Bool {
        let now = date ?? nowProvider()
        guard ledger.closeWorkday(containing: now, at: now, settings: settings) else { return false }
        publishAndSave()
        cancelTargetNotification(at: now)
        return true
    }

    @discardableResult
    func resumeToday(at date: Date? = nil) -> Bool {
        let now = date ?? nowProvider()
        guard ledger.resumeWorkday(containing: now, settings: settings) else { return false }
        _ = ledger.recordActivity(at: now, settings: settings)
        publishAndSave()
        refreshTargetNotification(at: now)
        return true
    }

    @discardableResult
    func correctRecord(_ id: UUID, startAt: Date, endAt: Date) -> Bool {
        guard ledger.correctRecord(id, startAt: startAt, endAt: endAt) else { return false }
        publishAndSave()
        if let record = records.first(where: { $0.id == id }) {
            notificationManager.cancelWorktimeTarget(workDate: record.workDate)
        }
        return true
    }

    @discardableResult
    func setManualRecord(on workDate: Date, startAt: Date, endAt: Date) -> Bool {
        let now = nowProvider()
        guard ledger.setManualRecord(
            on: workDate,
            startAt: startAt,
            endAt: endAt,
            updatedAt: now
        ) else { return false }
        publishAndSave()
        notificationManager.cancelWorktimeTarget(workDate: workDate.startOfLocalDay)
        return true
    }

    func refreshTargetNotification(at date: Date? = nil) {
        let now = date ?? nowProvider()
        guard settings.isEnabled, let record = record(on: now), !record.isClosed else {
            cancelTargetNotification(at: now)
            return
        }
        let expectedEndAt = record.expectedEndAt(targetMinutes: settings.dailyTargetMinutes)
        guard expectedEndAt > nowProvider() else {
            notificationManager.cancelWorktimeTarget(workDate: record.workDate)
            return
        }
        notificationManager.scheduleWorktimeTarget(
            workDate: record.workDate,
            startAt: record.effectiveStartAt,
            expectedEndAt: expectedEndAt,
            targetMinutes: settings.dailyTargetMinutes
        )
    }

    func clearPersistenceMessage() {
        persistenceMessage = nil
    }

    private func startMonitoring() {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.sampleNow()
                let seconds = max(60, self.settings.pollingMinutes * 60)
                do {
                    try await Task.sleep(for: .seconds(seconds))
                } catch {
                    return
                }
            }
        }
    }

    private func restartMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        startMonitoring()
    }

    private func cancelTargetNotification(at date: Date? = nil) {
        let now = date ?? nowProvider()
        let workDate = WorktimeLedger.workDate(
            for: now,
            boundaryMinutes: settings.workdayBoundaryMinutes
        )
        notificationManager.cancelWorktimeTarget(workDate: workDate)
    }

    private func publishAndSave() {
        records = ledger.records
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: dataURL.path) else {
            ledger = WorktimeLedger()
            records = []
            save()
            return
        }

        do {
            let data = try Data(contentsOf: dataURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(WorktimePersistedState.self, from: data)
            settings = state.settings.normalized
            ledger = WorktimeLedger(records: state.records)
            records = state.records
        } catch {
            recoverFromUnreadableData(error)
        }
    }

    private func save() {
        guard !persistenceBlocked else { return }
        let state = WorktimePersistedState(settings: settings, records: ledger.records)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(state).write(to: dataURL, options: .atomic)
        } catch {
            persistenceMessage = "工时数据保存失败：\(error.localizedDescription)"
        }
    }

    private func recoverFromUnreadableData(_ decodingError: Error) {
        let backupURL = dataURL
            .deletingLastPathComponent()
            .appendingPathComponent("worktime-corrupt-\(Int(nowProvider().timeIntervalSince1970)).json")
        do {
            try FileManager.default.copyItem(at: dataURL, to: backupURL)
            ledger = WorktimeLedger()
            records = []
            save()
            persistenceMessage = "工时数据无法读取，原文件已备份为 \(backupURL.lastPathComponent)。"
        } catch {
            persistenceBlocked = true
            persistenceMessage = "工时数据无法读取且无法备份，已停止写入：\(decodingError.localizedDescription)"
        }
    }
}
