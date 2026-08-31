import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingTaskEditor = false
    @State private var showingMeetingEditor = false
    @State private var showingBatchAdd = false
    @State private var editingTask: TaskItem?
    @State private var editingMeeting: MeetingItem?
    @State private var subtaskParent: TaskItem?

    private var todayTasks: [TaskItem] {
        let tasks = store.tasks(on: Date())
        let visibleIDs = Set(tasks.map(\.id))
        var ordered: [TaskItem] = []
        var insertedIDs: Set<UUID> = []

        for task in tasks where task.parentTaskID.map({ !visibleIDs.contains($0) }) ?? true {
            ordered.append(task)
            insertedIDs.insert(task.id)
            for subtask in tasks where subtask.parentTaskID == task.id {
                ordered.append(subtask)
                insertedIDs.insert(subtask.id)
            }
        }
        ordered.append(contentsOf: tasks.filter { !insertedIDs.contains($0.id) })
        return ordered
    }
    private var todayMeetings: [MeetingItem] { store.meetings(on: Date()) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if store.isDayFinalized(context.date) {
                DayClosureView(
                    destination: .today,
                    date: context.date,
                    displayName: store.settings.displayName
                )
            } else {
                todayWorkspace
            }
        }
        .sheet(isPresented: $showingTaskEditor) {
            TaskEditorSheet(defaultDate: Date(), task: editingTask)
                .environmentObject(store)
        }
        .sheet(isPresented: $showingMeetingEditor) {
            MeetingEditorSheet(defaultDate: Date(), meeting: editingMeeting)
                .environmentObject(store)
        }
        .sheet(isPresented: $showingBatchAdd) {
            BatchAddSheet()
                .environmentObject(store)
        }
        .sheet(item: $subtaskParent) { parent in
            TaskEditorSheet(
                defaultDate: parent.scheduledDate ?? Date(),
                parentTask: parent
            )
            .environmentObject(store)
        }
    }

    private var todayWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageHeader

                WorktimeSummaryCard()

                if let activeTask = store.activeTask {
                    FocusTimerCard(task: activeTask)
                }

                HStack(alignment: .top, spacing: 18) {
                    taskPanel
                        .frame(maxWidth: .infinity)
                    meetingPanel
                        .frame(width: 300)
                }
            }
            .yiRiPage()
        }
    }

    private var pageHeader: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(DateFormatter.yiRiDay.string(from: context.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(greeting(for: context.date))
                        .font(.system(size: 28, weight: .medium))
                }
                Spacer()
                Button {
                    showingBatchAdd = true
                } label: {
                    Label("批量补录", systemImage: "calendar.badge.plus")
                }
                Button {
                    editingTask = nil
                    showingTaskEditor = true
                } label: {
                    Label("添加任务", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func greeting(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return "早上好，先制定今天的计划吧"
        case 12..<18:
            return "下午好，继续为今天的目标加油"
        case 18..<24:
            return "晚上好，记得完成今天的复盘"
        default:
            return "夜深了，记录一下就早点休息吧"
        }
    }

    private var taskPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                let completed = todayTasks.filter(\.isCompleted).count
                let totalMinutes = todayTasks.reduce(0) { $0 + $1.estimatedMinutes }
                SectionHeader(
                    title: "今日计划",
                    subtitle: "\(completed) / \(todayTasks.count) 已完成 · 计划 \(totalMinutes.durationText)"
                )

                Divider()

                if todayTasks.isEmpty {
                    EmptyState(systemImage: "checklist", title: "今天还没有任务", detail: "添加一个任务，或从模版批量补录。")
                } else {
                    VStack(spacing: 0) {
                        ForEach(todayTasks) { task in
                            TodayTaskRow(task: task) {
                                editingTask = task
                                showingTaskEditor = true
                            } onAddSubtask: {
                                subtaskParent = task
                            }
                            if task.id != todayTasks.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    private var meetingPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "日程", subtitle: "\(todayMeetings.count) 场会议 · 手动录入")
                    Spacer()
                    Button {
                        editingMeeting = nil
                        showingMeetingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("添加会议")
                }

                Divider()

                if todayMeetings.isEmpty {
                    EmptyState(systemImage: "calendar", title: "今天没有会议", detail: "会议暂不连接外部日历。")
                } else {
                    ForEach(todayMeetings) { meeting in
                        HStack(alignment: .top, spacing: 12) {
                            Text(DateFormatter.yiRiTime.string(from: meeting.startDate))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(meeting.title)
                                    .font(.subheadline.weight(.medium))
                                Text("\(meeting.durationMinutes) 分钟 · \(meeting.location.isEmpty ? "未设置地点" : meeting.location)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(YiRiTheme.accentSoft.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contextMenu {
                            Button("编辑会议") {
                                editingMeeting = meeting
                                showingMeetingEditor = true
                            }
                            Divider()
                            Button("删除会议", role: .destructive) {
                                store.deleteMeeting(meeting.id)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct FocusTimerCard: View {
    @EnvironmentObject private var store: AppStore
    let task: TaskItem

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = store.elapsedSeconds(at: context.date)
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(store.timerStartedAt == nil ? "已暂停" : "专注中", systemImage: store.timerStartedAt == nil ? "pause.circle.fill" : "circle.fill")
                        .font(.caption.weight(.medium))
                    Text(task.title)
                        .font(.title3.weight(.medium))
                    Text("预计 \(task.estimatedMinutes.durationText) · 达到预计时间时会提醒")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(Self.timerText(elapsed))
                        .font(.system(size: 34, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    Text("已专注 / 预计 \(Self.timerText(task.estimatedMinutes * 60))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button {
                        store.timerStartedAt == nil ? store.resumeActiveTask() : store.pauseActiveTask()
                    } label: {
                        Image(systemName: store.timerStartedAt == nil ? "play.fill" : "pause.fill")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.bordered)
                    .help(store.timerStartedAt == nil ? "继续" : "暂停")

                    Button {
                        store.finishActiveTask()
                    } label: {
                        Image(systemName: "checkmark")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderedProminent)
                    .help("完成任务")
                }
            }
            .padding(20)
            .background(YiRiTheme.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
    }

    private static func timerText(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remaining = seconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remaining)
    }
}

private struct TodayTaskRow: View {
    @EnvironmentObject private var store: AppStore
    let task: TaskItem
    let onEdit: () -> Void
    let onAddSubtask: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { task.isCompleted },
                set: { store.setCompleted(task.id, completed: $0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if task.parentTaskID != nil {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundStyle(YiRiTheme.accent)
                    }
                    Text(task.title)
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                }
                Text("\(task.estimatedMinutes.durationText) · \(task.category)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.activeTaskID == task.id {
                Text("专注中")
                    .font(.caption)
                    .foregroundStyle(YiRiTheme.accent)
            } else if !task.isCompleted {
                Button("开始") {
                    store.startTask(task.id)
                }
                .buttonStyle(.bordered)
            }
            Menu {
                if task.parentTaskID == nil {
                    Button("添加子任务") { onAddSubtask() }
                    Divider()
                }
                Button("编辑") { onEdit() }
                Divider()
                Button("移到明天") { store.moveTask(task.id, to: Date().addingDays(1)) }
                Button("放回待安排") { store.moveTask(task.id, to: nil) }
                Divider()
                Button("删除", role: .destructive) { store.deleteTask(task.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            if task.parentTaskID == nil {
                Button("添加子任务") { onAddSubtask() }
            }
            Button("编辑任务") { onEdit() }
            if !task.isCompleted {
                Button("移到明天") { store.moveTask(task.id, to: Date().addingDays(1)) }
                Button("放回待安排") { store.moveTask(task.id, to: nil) }
            }
            Divider()
            Button("删除任务", role: .destructive) { store.deleteTask(task.id) }
        }
    }
}
