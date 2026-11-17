import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

private struct FocusTaskDrag: Codable, Transferable {
    let taskID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "com.local.yiri.focus-task"))
    }
}

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingTaskEditor = false
    @State private var showingMeetingEditor = false
    @State private var showingBatchAdd = false
    @State private var editingTask: TaskItem?
    @State private var editingMeeting: MeetingItem?
    @State private var subtaskParent: TaskItem?
    @State private var recommendationRequestedAt: Date?

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
                todayWorkspace(on: context.date)
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

    private func todayWorkspace(on date: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageHeader

                WorktimeSummaryCard()

                focusPanel

                HStack(alignment: .top, spacing: 18) {
                    taskPanel(on: date)
                        .frame(maxWidth: .infinity)
                    meetingPanel
                        .frame(width: 300)
                }
            }
            .yiRiPage()
        }
    }

    private var focusPanel: some View {
        let availableTasks = todayTasks.filter { !$0.isCompleted && store.focusSlot(for: $0.id) == nil }
        let occupiedCount = store.focusSlots.compactMap { $0 }.count
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(
                        title: "专注槽位",
                        subtitle: "\(occupiedCount) / \(store.focusSlots.count) 已占用"
                    )
                    Spacer()
                    Button {
                        store.pauseAllFocusTasks()
                    } label: {
                        Label("全部暂停", systemImage: "pause.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.hasRunningFocusTasks)
                    Button {
                        store.resumeAllFocusTasks()
                    } label: {
                        Label("全部恢复", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.hasPausedFocusTasks)
                    .help("继续所有已暂停的槽位计时")
                    Button {
                        store.stopAllFocusTasks()
                    } label: {
                        Label("全部移出", systemImage: "eject")
                    }
                    .buttonStyle(.bordered)
                    .disabled(occupiedCount == 0)
                    .help("移出槽位中的全部任务，保留已计时间")
                    Button {
                        store.addFocusSlot()
                    } label: {
                        Label("添加槽位", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    ForEach(store.focusSlots.indices, id: \.self) { slot in
                        if let session = store.focusSlots[slot],
                           let task = store.tasks.first(where: { $0.id == session.taskID }) {
                            FocusTimerCard(task: task, slot: slot, isRunning: session.startedAt != nil)
                        } else {
                            EmptyFocusSlotCard(slot: slot, availableTasks: availableTasks)
                        }
                    }
                }
            }
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

    private func taskPanel(on date: Date) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                let completed = todayTasks.filter(\.isCompleted).count
                let totalMinutes = todayTasks.reduce(0) { $0 + $1.estimatedMinutes }
                HStack {
                    SectionHeader(
                        title: "今日计划",
                        subtitle: "\(completed) / \(todayTasks.count) 已完成 · 计划 \(totalMinutes.durationText)"
                    )
                    Spacer()
                    Button {
                        let now = Date()
                        recommendationRequestedAt = recommendationRequestedAt?.startOfLocalDay == now.startOfLocalDay ? nil : now
                    } label: {
                        Label("推荐先做", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                }

                if recommendationRequestedAt?.startOfLocalDay == date.startOfLocalDay {
                    recommendationCard(store.recommendNextTask())
                }

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

    private func recommendationCard(_ recommendation: NextTaskRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch recommendation {
            case .noPendingTasks:
                Text("今日计划里没有待做的任务。")
            case .focusInProgress:
                Text("今日待办都已开始计时。")
            case .focusSlotsFull:
                Text("槽位已满。可以完成或移出一项任务，也可以添加槽位。")
            case .meetingInProgress:
                Text("当前有会议，会议结束后可以查看推荐。")
            case .noTaskFits(let availableMinutes):
                Text(availableMinutes == 0
                     ? "下一场会议快开始了，可以先准备会议。"
                     : "预留 5 分钟准备会议后，还有 \(availableMinutes) 分钟，当前没有预计能做完的任务。")
            case .task(let task, let minutes, let reason, let availableMinutes):
                HStack {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(store.focusSlot(for: task.id) == nil ? "开始专注" : "继续专注") {
                        let now = Date()
                        if case .task(let current, _, _, _) = store.recommendNextTask(at: now), current.id == task.id {
                            store.startTask(task.id)
                        } else {
                            recommendationRequestedAt = now
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Text("预计还需约 \(minutes.durationText) · \(reason)")
                    .foregroundStyle(.secondary)
                if let availableMinutes {
                    Text("预留 5 分钟准备会议后，还有 \(availableMinutes.durationText)。")
                        .foregroundStyle(.secondary)
                } else {
                    Text("今天没有后续会议，优先安排预计用时较长的任务。")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(YiRiTheme.accentSoft.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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

private struct EmptyFocusSlotCard: View {
    @EnvironmentObject private var store: AppStore
    @State private var isDropTargeted = false
    let slot: Int
    let availableTasks: [TaskItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("槽位 \(slot + 1) · 空闲", systemImage: "timer")
                    .foregroundStyle(.secondary)
                Spacer()
                if store.focusSlots.count > AppStore.defaultFocusSlotCount {
                    Button(role: .destructive) {
                        store.removeEmptyFocusSlot(slot)
                    } label: {
                        Label("删除槽位", systemImage: "trash")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .fixedSize()
                    .help("删除此空槽位")
                    .accessibilityLabel("删除槽位 \(slot + 1)")
                }
            }
            HStack(spacing: 10) {
                Text(isDropTargeted ? "松手开始计时" : "拖入今日任务")
                    .foregroundStyle(isDropTargeted ? YiRiTheme.accent : Color.secondary)
                Spacer(minLength: 0)
                Menu("选择任务") {
                    ForEach(availableTasks) { task in
                        Button(task.title) { store.startTodayTask(task.id, in: slot) }
                    }
                }
                .fixedSize()
                .disabled(availableTasks.isEmpty)
            }
        }
        .font(.caption)
        .focusSlotStyle(background: isDropTargeted ? YiRiTheme.accentSoft : YiRiTheme.inputBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isDropTargeted ? YiRiTheme.accent : YiRiTheme.border,
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [5, 4])
                )
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .dropDestination(for: FocusTaskDrag.self) { items, _ in
            guard items.count == 1, let item = items.first else { return false }
            return store.startTodayTask(item.taskID, in: slot)
        } isTargeted: { isDropTargeted = $0 }
    }
}

private struct FocusTimerCard: View {
    @EnvironmentObject private var store: AppStore
    let task: TaskItem
    let slot: Int
    let isRunning: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = store.elapsedSeconds(for: task, at: context.date)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("槽位 \(slot + 1) · \(isRunning ? "专注中" : "已暂停")", systemImage: isRunning ? "timer" : "pause.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        store.stopTask(task.id)
                    } label: {
                        Image(systemName: "eject")
                    }
                    .buttonStyle(.borderless)
                    .help("移出槽位并保留已计时间")
                    .accessibilityLabel("移出任务")
                }
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .help(task.title)
                HStack(spacing: 8) {
                    Text(Self.timerText(elapsed))
                        .font(.system(size: 25, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Button {
                        isRunning ? store.pauseTask(task.id) : store.resumeTask(task.id)
                    } label: {
                        Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .help(isRunning ? "暂停" : "继续")
                    .accessibilityLabel(isRunning ? "暂停计时" : "继续计时")

                    Button {
                        store.setCompleted(task.id, completed: true)
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("完成任务")
                    .accessibilityLabel("完成任务")
                }
                Text("预计 \(task.estimatedMinutes.durationText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .focusSlotStyle(background: YiRiTheme.accentSoft)
        }
    }

    private static func timerText(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remaining = seconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remaining)
    }
}

private extension View {
    func focusSlotStyle(background: Color) -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 114, alignment: .topLeading)
            .background(background, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct TodayTaskRow: View {
    @EnvironmentObject private var store: AppStore
    let task: TaskItem
    let onEdit: () -> Void
    let onAddSubtask: () -> Void

    var body: some View {
        let assignedSlot = store.focusSlot(for: task.id)
        let isRunning = assignedSlot.flatMap { store.focusSlots[$0]?.startedAt } != nil
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { task.isCompleted },
                set: { store.setCompleted(task.id, completed: $0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            if !task.isCompleted, assignedSlot == nil {
                taskLabel
                    .draggable(FocusTaskDrag(taskID: task.id)) {
                        Label(task.title, systemImage: "timer")
                            .padding(10)
                            .background(YiRiTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .accessibilityHint("可拖到空闲专注槽位开始计时")
            } else {
                taskLabel
            }
            if let assignedSlot {
                Label("槽位 \(assignedSlot + 1) · \(isRunning ? "专注中" : "已暂停")",
                      systemImage: isRunning ? "timer" : "pause.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(YiRiTheme.panel, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(isRunning ? YiRiTheme.accent.opacity(0.55) : YiRiTheme.border)
                    }
            } else if !task.isCompleted {
                Button("开始") {
                    store.startTask(task.id)
                }
                .buttonStyle(.bordered)
                .disabled(!store.hasEmptyFocusSlot)
                .help(store.hasEmptyFocusSlot ? "在空闲槽位开始计时" : "请先腾出或添加一个槽位")
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
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background {
            if assignedSlot != nil {
                RoundedRectangle(cornerRadius: 9)
                    .fill(isRunning ? YiRiTheme.accentSoft : YiRiTheme.warm)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(isRunning ? YiRiTheme.accent : Color.secondary.opacity(0.55))
                            .frame(width: 3)
                            .padding(.vertical, 8)
                    }
            }
        }
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

    private var taskLabel: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
