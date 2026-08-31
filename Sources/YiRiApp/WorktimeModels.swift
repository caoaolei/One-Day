import Foundation

struct WorktimeSettings: Codable, Hashable {
    var isEnabled = false
    var launchAtLogin = false
    var pollingMinutes = 1
    var workdayBoundaryMinutes = 6 * 60
    var dailyTargetMinutes = 8 * 60

    var normalized: WorktimeSettings {
        var value = self
        value.pollingMinutes = max(1, pollingMinutes)
        value.workdayBoundaryMinutes = min(12 * 60, max(0, workdayBoundaryMinutes))
        value.dailyTargetMinutes = min(16 * 60, max(60, dailyTargetMinutes))
        return value
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        pollingMinutes = try container.decodeIfPresent(Int.self, forKey: .pollingMinutes) ?? 1
        workdayBoundaryMinutes = try container.decodeIfPresent(Int.self, forKey: .workdayBoundaryMinutes) ?? 6 * 60
        dailyTargetMinutes = try container.decodeIfPresent(Int.self, forKey: .dailyTargetMinutes) ?? 8 * 60
        self = normalized
    }
}

struct DailyWorktimeRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var workDate: Date
    var firstActivityAt: Date
    var lastActivityAt: Date
    var manualStartAt: Date?
    var manualEndAt: Date?
    var isClosed = false
    var createdAt = Date()
    var updatedAt = Date()

    var effectiveStartAt: Date {
        manualStartAt ?? firstActivityAt
    }

    var effectiveEndAt: Date {
        manualEndAt ?? lastActivityAt
    }

    var spanSeconds: Int {
        max(0, Int(effectiveEndAt.timeIntervalSince(effectiveStartAt)))
    }

    var isManuallyAdjusted: Bool {
        manualStartAt != nil || manualEndAt != nil
    }

    func expectedEndAt(targetMinutes: Int) -> Date {
        effectiveStartAt.addingTimeInterval(TimeInterval(max(1, targetMinutes) * 60))
    }

    func goalProgress(targetMinutes: Int) -> Double {
        Double(spanSeconds) / Double(max(1, targetMinutes) * 60)
    }
}

struct WorktimePersistedState: Codable {
    var schemaVersion = 1
    var settings = WorktimeSettings()
    var records: [DailyWorktimeRecord] = []

    init(settings: WorktimeSettings = WorktimeSettings(), records: [DailyWorktimeRecord] = []) {
        self.settings = settings.normalized
        self.records = records
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        settings = (try container.decodeIfPresent(WorktimeSettings.self, forKey: .settings) ?? WorktimeSettings()).normalized
        records = try container.decodeIfPresent([DailyWorktimeRecord].self, forKey: .records) ?? []
    }
}

enum WorktimeDisplayStatus: Equatable {
    case disabled
    case waiting
    case recording
    case away
    case ended
    case unavailable

    var title: String {
        switch self {
        case .disabled: "自动记录未开启"
        case .waiting: "等待第一次活动"
        case .recording: "自动记录中"
        case .away: "暂时没有活动"
        case .ended: "今日记录已结束"
        case .unavailable: "暂时无法读取活动状态"
        }
    }

    var symbol: String {
        switch self {
        case .disabled: "pause.circle"
        case .waiting: "clock"
        case .recording: "circle.fill"
        case .away: "moon.zzz"
        case .ended: "checkmark.circle.fill"
        case .unavailable: "exclamationmark.triangle"
        }
    }
}

struct WorktimeLedger {
    private(set) var records: [DailyWorktimeRecord]

    init(records: [DailyWorktimeRecord] = []) {
        self.records = records
    }

    func record(on workDate: Date) -> DailyWorktimeRecord? {
        records.first { Calendar.yiRi.isDate($0.workDate, inSameDayAs: workDate) }
    }

    @discardableResult
    mutating func recordActivity(at activityAt: Date, settings: WorktimeSettings) -> Bool {
        let workDate = Self.workDate(for: activityAt, boundaryMinutes: settings.workdayBoundaryMinutes)
        if let index = records.firstIndex(where: { Calendar.yiRi.isDate($0.workDate, inSameDayAs: workDate) }) {
            guard !records[index].isClosed else { return false }
            let oldFirst = records[index].firstActivityAt
            let oldLast = records[index].lastActivityAt
            records[index].firstActivityAt = min(oldFirst, activityAt)
            records[index].lastActivityAt = max(oldLast, activityAt)
            guard records[index].firstActivityAt != oldFirst || records[index].lastActivityAt != oldLast else {
                return false
            }
            records[index].updatedAt = activityAt
            return true
        }

        records.append(DailyWorktimeRecord(
            workDate: workDate,
            firstActivityAt: activityAt,
            lastActivityAt: activityAt,
            createdAt: activityAt,
            updatedAt: activityAt
        ))
        return true
    }

    @discardableResult
    mutating func closeWorkday(containing timestamp: Date, at endAt: Date, settings: WorktimeSettings) -> Bool {
        let workDate = Self.workDate(for: timestamp, boundaryMinutes: settings.workdayBoundaryMinutes)
        guard let index = records.firstIndex(where: { Calendar.yiRi.isDate($0.workDate, inSameDayAs: workDate) }) else {
            return false
        }
        let startAt = records[index].effectiveStartAt
        records[index].manualEndAt = max(startAt, endAt)
        records[index].isClosed = true
        records[index].updatedAt = endAt
        return true
    }

    @discardableResult
    mutating func resumeWorkday(containing timestamp: Date, settings: WorktimeSettings) -> Bool {
        let workDate = Self.workDate(for: timestamp, boundaryMinutes: settings.workdayBoundaryMinutes)
        guard let index = records.firstIndex(where: { Calendar.yiRi.isDate($0.workDate, inSameDayAs: workDate) }) else {
            return false
        }
        records[index].manualEndAt = nil
        records[index].isClosed = false
        records[index].updatedAt = timestamp
        return true
    }

    @discardableResult
    mutating func correctRecord(_ id: UUID, startAt: Date, endAt: Date) -> Bool {
        guard endAt >= startAt, let index = records.firstIndex(where: { $0.id == id }) else { return false }
        records[index].manualStartAt = startAt
        records[index].manualEndAt = endAt
        records[index].isClosed = true
        records[index].updatedAt = Date()
        return true
    }

    @discardableResult
    mutating func setManualRecord(
        on workDate: Date,
        startAt: Date,
        endAt: Date,
        updatedAt: Date = Date()
    ) -> Bool {
        guard endAt >= startAt else { return false }
        let normalizedWorkDate = workDate.startOfLocalDay

        if let index = records.firstIndex(where: {
            Calendar.yiRi.isDate($0.workDate, inSameDayAs: normalizedWorkDate)
        }) {
            records[index].manualStartAt = startAt
            records[index].manualEndAt = endAt
            records[index].isClosed = true
            records[index].updatedAt = updatedAt
            return true
        }

        records.append(DailyWorktimeRecord(
            workDate: normalizedWorkDate,
            firstActivityAt: startAt,
            lastActivityAt: endAt,
            manualStartAt: startAt,
            manualEndAt: endAt,
            isClosed: true,
            createdAt: updatedAt,
            updatedAt: updatedAt
        ))
        return true
    }

    static func workDate(for timestamp: Date, boundaryMinutes: Int) -> Date {
        let boundary = min(12 * 60, max(0, boundaryMinutes))
        let components = Calendar.yiRi.dateComponents([.hour, .minute], from: timestamp)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if minutes < boundary {
            return timestamp.addingDays(-1)
        }
        return timestamp.startOfLocalDay
    }
}
