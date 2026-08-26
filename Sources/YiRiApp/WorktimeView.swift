import SwiftUI

struct WorktimeView: View {
    @EnvironmentObject private var worktime: WorktimeController
    @EnvironmentObject private var store: AppStore
    @State private var editingRecord: DailyWorktimeRecord?
    @State private var displayedMonth = Date()

    private var previousRecords: [DailyWorktimeRecord] {
        let current = worktime.record(on: Date())?.id
        return worktime.sortedRecords.filter { $0.id != current }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                WorktimeSummaryCard()
                WorktimeCalendarBoard(
                    displayedMonth: $displayedMonth,
                    records: worktime.records,
                    targetMinutes: worktime.settings.dailyTargetMinutes
                ) { record in
                    if !Calendar.yiRi.isDateInToday(record.workDate) || !store.isDayFinalized(Date()) {
                        editingRecord = record
                    }
                }

                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            title: "近期明细",
                            subtitle: "工时按每天最晚活动时间减最早活动时间计算，午休也包含在内"
                        )
                        Divider()

                        if previousRecords.isEmpty {
                            EmptyState(
                                systemImage: "calendar.badge.clock",
                                title: "还没有历史工时",
                                detail: "开启自动记录后，每天的第一和最后活动时间会保存在这里。"
                            )
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(previousRecords.prefix(12)) { record in
                                    WorktimeHistoryRow(
                                        record: record,
                                        targetMinutes: worktime.settings.dailyTargetMinutes
                                    ) {
                                        editingRecord = record
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .yiRiPage()
        }
        .sheet(item: $editingRecord) { record in
            WorktimeRecordEditorSheet(record: record)
                .environmentObject(worktime)
        }
        .alert(
            "工时数据提示",
            isPresented: Binding(
                get: { worktime.persistenceMessage != nil },
                set: { presented in
                    if !presented { worktime.clearPersistenceMessage() }
                }
            )
        ) {
            Button("知道了") { worktime.clearPersistenceMessage() }
        } message: {
            Text(worktime.persistenceMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("本机自动记录 · 月度一览")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("工时看板")
                    .font(.system(size: 28, weight: .medium))
            }
            Spacer()
            if let today = worktime.record(on: Date()), !store.isDayFinalized(Date()) {
                Button {
                    editingRecord = today
                } label: {
                    Label("修正今天", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
            }
            Button {
                worktime.sampleNow()
            } label: {
                Label("立即检测", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(!worktime.settings.isEnabled)
        }
    }
}

struct WorktimeSummaryCard: View {
    @EnvironmentObject private var worktime: WorktimeController
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let status = worktime.status(at: context.date)
            let record = worktime.record(on: context.date)

            Panel {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Label("今日工时", systemImage: "briefcase")
                            .font(.headline)
                        Spacer()
                        Label(status.title, systemImage: status.symbol)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(status == .recording ? YiRiTheme.accent : Color.secondary)
                    }

                    if let record {
                        let expectedEnd = record.expectedEndAt(targetMinutes: worktime.settings.dailyTargetMinutes)
                        HStack(spacing: 24) {
                            WorktimeMetric(
                                value: DateFormatter.yiRiTime.string(from: record.effectiveStartAt),
                                label: "上班时间"
                            )
                            WorktimeMetric(
                                value: DateFormatter.yiRiTime.string(from: record.effectiveEndAt),
                                label: record.isClosed ? "下班时间" : "最新活动"
                            )
                            WorktimeMetric(
                                value: record.spanSeconds.worktimeDurationText,
                                label: "今日工时"
                            )
                            WorktimeMetric(
                                value: DateFormatter.yiRiTime.string(from: expectedEnd),
                                label: "预计下班"
                            )
                        }

                        WorktimeGoalProgressBar(
                            elapsedSeconds: record.spanSeconds,
                            targetMinutes: worktime.settings.dailyTargetMinutes
                        )

                        HStack {
                            Text(goalHint(record: record, now: context.date))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if record.isClosed {
                                if store.isDayFinalized(context.date) {
                                    Label("复盘已封存", systemImage: "lock.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button("继续记录") {
                                        worktime.resumeToday(at: context.date)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            } else {
                                Button("结束今天") {
                                    worktime.endToday(at: context.date)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    } else if worktime.settings.isEnabled {
                        HStack(spacing: 12) {
                            Image(systemName: "cursorarrow.motionlines")
                                .font(.title2)
                                .foregroundStyle(YiRiTheme.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("正在等待第一次键鼠活动")
                                    .font(.subheadline.weight(.medium))
                                Text("记录开始后会按每日目标计算预计下班时间，并安排提醒。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("开启后自动记录每天最早和最晚活动时间")
                                    .font(.subheadline.weight(.medium))
                                Text("数据只保存在本机，不读取按键内容或窗口内容。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("开启自动工时") {
                                var settings = worktime.settings
                                settings.isEnabled = true
                                worktime.updateSettings(settings)
                                Task {
                                    if await NotificationManager.shared.requestAuthorization() {
                                        worktime.refreshTargetNotification()
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
    }

    private func goalHint(record: DailyWorktimeRecord, now: Date) -> String {
        if record.isClosed { return "本日记录已结束，午休与中间离开均计入工时" }
        let targetSeconds = worktime.settings.dailyTargetMinutes * 60
        if record.spanSeconds >= targetSeconds { return "今天的目标工时已经达到，辛苦了" }
        let expectedEnd = record.expectedEndAt(targetMinutes: worktime.settings.dailyTargetMinutes)
        if expectedEnd <= now { return "已到预计下班时间；最新活动会继续更新今日工时" }
        let remaining = max(0, Int(expectedEnd.timeIntervalSince(now)))
        return "距离预计下班约 \(remaining.worktimeDurationText) · 午休与中间离开均计入"
    }
}

struct WorktimeGoalProgressBar: View {
    let elapsedSeconds: Int
    let targetMinutes: Int
    var compact = false

    private var progress: Double {
        Double(elapsedSeconds) / Double(max(1, targetMinutes) * 60)
    }

    private var clampedProgress: Double {
        min(1, max(0, progress))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 0 : 7) {
            GeometryReader { proxy in
                let fillWidth = proxy.size.width * clampedProgress
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(YiRiTheme.secondaryPanel)
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: progress >= 1
                                    ? [YiRiTheme.completionHighlight, YiRiTheme.accent]
                                    : [YiRiTheme.accent.opacity(0.58), YiRiTheme.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth)
                    if !compact, fillWidth > 9 {
                        Circle()
                            .fill(Color.white)
                            .overlay { Circle().stroke(YiRiTheme.accent, lineWidth: 2) }
                            .frame(width: 10, height: 10)
                            .offset(x: max(0, fillWidth - 10))
                            .shadow(color: YiRiTheme.accent.opacity(0.22), radius: 3)
                    }
                }
            }
            .frame(height: compact ? 6 : 12)

            if !compact {
                HStack {
                    Text("已记录 \(elapsedSeconds.worktimeDurationText) / 目标 \(targetMinutes.worktimeTargetText)")
                    Spacer()
                    if progress >= 1 {
                        Label("已达标", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(YiRiTheme.accent)
                    } else {
                        Text("\(Int(progress * 100))%")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
        .animation(.easeOut(duration: 0.35), value: clampedProgress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("工时目标进度 \(Int(progress * 100)) 百分比")
    }
}

private struct WorktimeCalendarBoard: View {
    @Binding var displayedMonth: Date
    let records: [DailyWorktimeRecord]
    let targetMinutes: Int
    let onSelect: (DailyWorktimeRecord) -> Void

    private let calendar = Calendar.yiRi
    private let weekdayTitles = ["一", "二", "三", "四", "五", "六", "日"]
    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 72, maximum: .infinity), spacing: 8),
        count: 7
    )

    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth.startOfLocalDay
    }

    private var monthRecords: [DailyWorktimeRecord] {
        guard let interval = calendar.dateInterval(of: .month, for: monthStart) else { return [] }
        return records.filter { interval.contains($0.workDate) }
    }

    private var calendarDays: [Date?] {
        guard let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingCount = (weekday + 5) % 7
        var days = Array<Date?>(repeating: nil, count: leadingCount)
        days.append(contentsOf: dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: monthStart)
        })
        let trailingCount = (7 - days.count % 7) % 7
        days.append(contentsOf: Array<Date?>(repeating: nil, count: trailingCount))
        return days
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("月度工时")
                            .font(.headline)
                        Text("每天的上班、下班时间与目标进度")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { moveMonth(-1) } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    Text(DateFormatter.yiRiMonth.string(from: monthStart))
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 100)
                    Button { moveMonth(1) } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                    Button("本月") { displayedMonth = Date() }
                        .buttonStyle(.bordered)
                }

                HStack(spacing: 12) {
                    WorktimeMonthStat(value: "\(monthRecords.count)", label: "记录天数")
                    WorktimeMonthStat(value: totalSeconds.worktimeDurationText, label: "累计工时")
                    WorktimeMonthStat(value: averageSeconds.worktimeDurationText, label: "日均工时")
                    WorktimeMonthStat(value: "\(reachedTargetCount)", label: "达标天数")
                }

                Divider()

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(weekdayTitles, id: \.self) { title in
                        Text(title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(Array(calendarDays.enumerated()), id: \.offset) { _, day in
                        if let day {
                            let record = record(for: day)
                            Button {
                                if let record { onSelect(record) }
                            } label: {
                                WorktimeCalendarDayCell(
                                    day: day,
                                    record: record,
                                    targetMinutes: targetMinutes
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(minHeight: 100)
                        }
                    }
                }
            }
        }
    }

    private var totalSeconds: Int {
        monthRecords.reduce(0) { $0 + $1.spanSeconds }
    }

    private var averageSeconds: Int {
        monthRecords.isEmpty ? 0 : totalSeconds / monthRecords.count
    }

    private var reachedTargetCount: Int {
        monthRecords.filter { $0.spanSeconds >= targetMinutes * 60 }.count
    }

    private func record(for day: Date) -> DailyWorktimeRecord? {
        monthRecords.first { calendar.isDate($0.workDate, inSameDayAs: day) }
    }

    private func moveMonth(_ offset: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: offset, to: monthStart) ?? displayedMonth
    }
}

private struct WorktimeCalendarDayCell: View {
    let day: Date
    let record: DailyWorktimeRecord?
    let targetMinutes: Int

    private var isToday: Bool { Calendar.yiRi.isDateInToday(day) }
    private var reachedTarget: Bool { (record?.spanSeconds ?? 0) >= targetMinutes * 60 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(Calendar.yiRi.component(.day, from: day))")
                    .font(.caption.weight(isToday ? .bold : .medium))
                Spacer()
                if reachedTarget {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(YiRiTheme.accent)
                }
            }

            if let record {
                Text("上 \(DateFormatter.yiRiTime.string(from: record.effectiveStartAt))")
                    .lineLimit(1)
                Text("下 \(DateFormatter.yiRiTime.string(from: record.effectiveEndAt))")
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(record.spanSeconds.worktimeDurationText)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                WorktimeGoalProgressBar(
                    elapsedSeconds: record.spanSeconds,
                    targetMinutes: targetMinutes,
                    compact: true
                )
            } else {
                Spacer()
                Text("—")
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .font(.system(size: 10, design: .rounded))
        .monospacedDigit()
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .background(reachedTarget ? YiRiTheme.completionSoft.opacity(0.66) : YiRiTheme.secondaryPanel.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isToday ? YiRiTheme.accent : (reachedTarget ? YiRiTheme.completionBorder : YiRiTheme.border.opacity(0.62)),
                    lineWidth: isToday ? 1.5 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct WorktimeMonthStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(YiRiTheme.accentSoft.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct WorktimeMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorktimeHistoryRow: View {
    let record: DailyWorktimeRecord
    let targetMinutes: Int
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(DateFormatter.yiRiDay.string(from: record.workDate))
                    .font(.subheadline.weight(.semibold))
                Text(record.isManuallyAdjusted ? "手动修正" : "自动记录")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 150, alignment: .leading)

            Label(DateFormatter.yiRiTime.string(from: record.effectiveStartAt), systemImage: "play.circle")
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(DateFormatter.yiRiTime.string(from: record.effectiveEndAt), systemImage: "stop.circle")

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text(record.spanSeconds.worktimeDurationText)
                    .font(.headline.monospacedDigit())
                WorktimeGoalProgressBar(
                    elapsedSeconds: record.spanSeconds,
                    targetMinutes: targetMinutes,
                    compact: true
                )
                .frame(width: 90)
            }
            Button("修正") { onEdit() }
                .buttonStyle(.bordered)
        }
        .font(.caption)
        .padding(12)
        .background(YiRiTheme.secondaryPanel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(YiRiTheme.border.opacity(0.65), lineWidth: 1)
        }
    }
}

private struct WorktimeRecordEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var worktime: WorktimeController
    let record: DailyWorktimeRecord
    @State private var startAt: Date
    @State private var endAt: Date

    init(record: DailyWorktimeRecord) {
        self.record = record
        _startAt = State(initialValue: record.effectiveStartAt)
        _endAt = State(initialValue: record.effectiveEndAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("修正工时")
                    .font(.title2.weight(.semibold))
                Text(DateFormatter.yiRiDay.string(from: record.workDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Form {
                DatePicker("开始时间", selection: $startAt, displayedComponents: [.date, .hourAndMinute])
                DatePicker("结束时间", selection: $endAt, displayedComponents: [.date, .hourAndMinute])
                LabeledContent("修正后工时") {
                    Text(max(0, Int(endAt.timeIntervalSince(startAt))).worktimeDurationText)
                        .monospacedDigit()
                }
            }
            .formStyle(.grouped)

            HStack {
                Text("保存后会以手动时间为准，并结束该日自动更新。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }
                Button("保存修正") {
                    if worktime.correctRecord(record.id, startAt: startAt, endAt: endAt) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(endAt < startAt)
            }
        }
        .padding(24)
        .frame(width: 540, height: 360)
    }
}

extension Int {
    var worktimeDurationText: String {
        guard self >= 60 else { return self > 0 ? "< 1 分钟" : "0 分钟" }
        let totalMinutes = self / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) 分钟" }
        return minutes == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes) 分"
    }

    var worktimeTargetText: String {
        let hours = self / 60
        let minutes = self % 60
        if minutes == 0 { return "\(hours) 小时" }
        if hours == 0 { return "\(minutes) 分钟" }
        return "\(hours) 小时 \(minutes) 分"
    }
}
