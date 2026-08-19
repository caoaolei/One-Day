import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case today = "今天"
    case board = "看板"
    case review = "复盘"
    case templates = "模版"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .board: "rectangle.3.group"
        case .review: "square.and.pencil"
        case .templates: "square.grid.2x2"
        }
    }
}

enum CarryOverPolicy: String, Codable, CaseIterable, Identifiable {
    case manual = "逐项决定（默认）"
    case tomorrow = "自动移到明天"
    case backlog = "保留在待安排"

    var id: String { rawValue }
}

struct TaskItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var category: String
    var estimatedMinutes: Int
    var actualSeconds: Int = 0
    var scheduledDate: Date?
    var isCompleted = false
    var note = ""
    var createdAt = Date()
    var completedAt: Date?

    var completionEffortText: String {
        guard actualSeconds > 0 else { return "手动完成" }
        if actualSeconds < 60 { return "专注不足 1 分钟" }
        return "专注 \(actualSeconds.secondsDurationText)"
    }
}

struct MeetingItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var startDate: Date
    var durationMinutes: Int
    var location: String
}

struct TemplateTask: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var category: String
    var estimatedMinutes: Int
}

struct TaskTemplate: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var detail: String
    var tasks: [TemplateTask]
    var isBuiltIn = false
}

struct DailyReview: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var note: String
    var savedAt = Date()
}

struct AppSettings: Codable, Hashable {
    var displayName: String?
    var morningReminderMinutes = 10 * 60 + 30
    var eveningReminderMinutes = 20 * 60
    var carryOverPolicy = CarryOverPolicy.manual
    var remindDoNotDisturb = true
    var notificationsAuthorized = false
}

struct PersistedState: Codable {
    var tasks: [TaskItem]
    var meetings: [MeetingItem]
    var templates: [TaskTemplate]
    var reviews: [DailyReview]
    var settings: AppSettings
    var activeTaskID: UUID?
    var timerStartedAt: Date?
    var timerAccumulatedSeconds: Int
}

struct EstimateSuggestion: Equatable {
    let minutes: Int
    let reason: String
}

struct PersistenceIssue: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

extension Calendar {
    static let yiRi = Calendar(identifier: .gregorian)
}

extension Date {
    var startOfLocalDay: Date { Calendar.yiRi.startOfDay(for: self) }

    func addingDays(_ value: Int) -> Date {
        Calendar.yiRi.date(byAdding: .day, value: value, to: startOfLocalDay) ?? self
    }
}

extension Int {
    var durationText: String {
        if self < 60 { return "\(self) 分钟" }
        let hours = self / 60
        let minutes = self % 60
        return minutes == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes) 分"
    }

    var secondsDurationText: String {
        let totalMinutes = self / 60
        return totalMinutes.durationText
    }
}
