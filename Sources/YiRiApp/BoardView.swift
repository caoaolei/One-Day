import SwiftUI

struct BoardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingTaskEditor = false
    @State private var showingCompletedHistory = false
    @State private var editingTask: TaskItem?
    @State private var highlightedCompletedID: UUID?

    private var overdue: [TaskItem] {
        store.overdueTasks()
    }

    private var todayPending: [TaskItem] {
        store.tasks(on: Date()).filter { !$0.isCompleted }
    }

    private var todayCompleted: [TaskItem] {
        store.completedToday()
    }

    private var completedHistoryCount: Int {
        store.earlierCompletedCount()
    }

    private var unplannedOrUpcoming: [TaskItem] {
        store.unplannedOrUpcomingTasks()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                HStack(alignment: .top, spacing: 14) {
                    BoardColumn(
                        title: "昨天",
                        subtitle: "含更早未完成",
                        tasks: overdue,
                        lane: .yesterday,
                        accent: false,
                        onEdit: edit,
                        onComplete: complete,
                        onMove: move
                    )
                    BoardColumn(
                        title: "今天待完成",
                        subtitle: "安排在今天",
                        tasks: todayPending,
                        lane: .todayPending,
                        accent: true,
                        onEdit: edit,
                        onComplete: complete,
                        onMove: move
                    )
                    TodayCompletedColumn(
                        tasks: todayCompleted,
                        historyCount: completedHistoryCount,
                        highlightedTaskID: highlightedCompletedID,
                        onShowHistory: { showingCompletedHistory = true },
                        onEdit: edit,
                        onRestore: restore,
                        onDelete: delete,
                        onMove: move
                    )
                }

                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            title: "待安排与未来",
                            subtitle: "这些任务也可以直接拖到上方三列"
                        )
                        Divider()
                        if unplannedOrUpcoming.isEmpty {
                            Text("暂无任务")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 56)
                        } else {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 240), spacing: 12)],
                                alignment: .leading,
                                spacing: 12
                            ) {
                                ForEach(unplannedOrUpcoming) { task in
                                    BoardTaskCard(
                                        task: task,
                                        accent: false,
                                        onEdit: { edit(task) },
                                        onComplete: { complete(task) }
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .yiRiPage()
        }
        .sheet(isPresented: $showingTaskEditor) {
            TaskEditorSheet(defaultDate: Date())
                .environmentObject(store)
        }
        .sheet(isPresented: $showingCompletedHistory) {
            CompletedHistorySheet()
                .environmentObject(store)
        }
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(defaultDate: task.scheduledDate ?? Date(), task: task)
                .environmentObject(store)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("所有任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("任务看板")
                    .font(.system(size: 28, weight: .medium))
                Label("拖动卡片即可调整日期和完成状态", systemImage: "hand.draw")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            Spacer()
            Button {
                showingTaskEditor = true
            } label: {
                Label("新建任务", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func edit(_ task: TaskItem) {
        editingTask = task
    }

    private func complete(_ task: TaskItem) {
        _ = move(task.id, .todayCompleted)
    }

    private func move(_ taskID: UUID, _ lane: BoardLane) -> Bool {
        var moved = false
        withAnimation(.easeOut(duration: 0.24)) {
            if case .todayCompleted = lane {
                highlightedCompletedID = taskID
            }
            moved = store.moveTask(taskID, to: lane)
            if !moved, highlightedCompletedID == taskID {
                highlightedCompletedID = nil
            }
        }

        if moved, case .todayCompleted = lane {
            clearCompletionHighlight(after: 1.1, taskID: taskID)
        }
        return moved
    }

    private func clearCompletionHighlight(after seconds: Double, taskID: UUID) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard highlightedCompletedID == taskID else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                highlightedCompletedID = nil
            }
        }
    }

    private func restore(_ task: TaskItem) {
        withAnimation(.easeInOut(duration: 0.22)) {
            store.setCompleted(task.id, completed: false)
        }
    }

    private func delete(_ task: TaskItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            store.deleteTask(task.id)
        }
    }
}

private struct BoardColumn: View {
    let title: String
    let subtitle: String
    let tasks: [TaskItem]
    let lane: BoardLane
    let accent: Bool
    let onEdit: (TaskItem) -> Void
    let onComplete: (TaskItem) -> Void
    let onMove: (UUID, BoardLane) -> Bool
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(isDropTargeted ? "松开即可移动到这里" : subtitle)
                        .font(.caption2)
                        .foregroundStyle(isDropTargeted ? YiRiTheme.accent : Color.secondary)
                }
                Spacer()
                CountBadge(count: tasks.count)
            }
            .padding(.horizontal, 3)

            if tasks.isEmpty {
                DropEmptyState(isTargeted: isDropTargeted)
            } else {
                ForEach(tasks) { task in
                    BoardTaskCard(
                        task: task,
                        accent: accent,
                        onEdit: { onEdit(task) },
                        onComplete: { onComplete(task) }
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 166, alignment: .top)
        .background(isDropTargeted ? YiRiTheme.accentSoft : YiRiTheme.secondaryPanel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isDropTargeted ? YiRiTheme.accent : YiRiTheme.border.opacity(0.7),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 1.6 : 1, dash: isDropTargeted ? [6, 4] : [])
                )
        }
        .dropDestination(for: String.self) { identifiers, _ in
            guard let value = identifiers.first, let taskID = UUID(uuidString: value) else { return false }
            return onMove(taskID, lane)
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.15)) {
                isDropTargeted = targeted
            }
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
    }
}

private struct TodayCompletedColumn: View {
    let tasks: [TaskItem]
    let historyCount: Int
    let highlightedTaskID: UUID?
    let onShowHistory: () -> Void
    let onEdit: (TaskItem) -> Void
    let onRestore: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onMove: (UUID, BoardLane) -> Bool
    @State private var isDropTargeted = false

    private var focusSeconds: Int {
        tasks.reduce(0) { $0 + max(0, $1.actualSeconds) }
    }

    private var focusText: String {
        guard focusSeconds > 0 else { return "—" }
        if focusSeconds < 60 { return "< 1 分钟" }
        return focusSeconds.secondsDurationText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今天已完成")
                        .font(.headline)
                    Text(isDropTargeted ? "松开即可标记完成" : "今日成果")
                        .font(.caption2)
                        .foregroundStyle(isDropTargeted ? YiRiTheme.accent : Color.secondary)
                }
                Spacer()
                CountBadge(count: tasks.count, completed: true)
            }
            .padding(.horizontal, 3)

            completionSummary

            historyButton

            if tasks.isEmpty {
                DropEmptyState(
                    isTargeted: isDropTargeted,
                    emptyText: "今天完成的任务会出现在这里"
                )
            } else {
                ForEach(tasks) { task in
                    CompletedTaskCard(
                        task: task,
                        highlighted: highlightedTaskID == task.id,
                        onEdit: { onEdit(task) },
                        onRestore: { onRestore(task) },
                        onDelete: { onDelete(task) }
                    )
                    .draggable(task.id.uuidString)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)),
                            removal: .opacity
                        )
                    )
                }
            }

        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 166, alignment: .top)
        .background(isDropTargeted ? YiRiTheme.completionSoft : YiRiTheme.completionColumn)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isDropTargeted ? YiRiTheme.accent : YiRiTheme.completionBorder.opacity(0.85),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 1.6 : 1, dash: isDropTargeted ? [6, 4] : [])
                )
        }
        .dropDestination(for: String.self) { identifiers, _ in
            guard let value = identifiers.first, let taskID = UUID(uuidString: value) else { return false }
            return onMove(taskID, .todayCompleted)
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.15)) {
                isDropTargeted = targeted
            }
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
    }

    private var completionSummary: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(YiRiTheme.panel.opacity(0.86))
                    .frame(width: 36, height: 36)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(YiRiTheme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tasks.isEmpty ? "今日成果" : "完成 \(tasks.count) 项")
                    .font(.subheadline.weight(.semibold))
                Text(tasks.isEmpty ? "每一次完成都值得记录" : "今天已经向前走了一步")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                Text(focusText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text("实际专注")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(11)
        .background {
            LinearGradient(
                colors: [YiRiTheme.completionSoft, YiRiTheme.completionHighlight.opacity(0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(YiRiTheme.completionBorder.opacity(0.75), lineWidth: 1)
        }
    }

    private var historyButton: some View {
        Button {
            onShowHistory()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(YiRiTheme.accent)
                Text("查看之前完成")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(historyCount) 项")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(YiRiTheme.panel.opacity(historyCount > 0 ? 0.82 : 0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(YiRiTheme.completionBorder.opacity(0.55), lineWidth: 1)
        }
        .disabled(historyCount == 0)
        .help(historyCount == 0 ? "还没有之前完成的任务" : "查看今天以前完成的全部任务")
    }
}

private struct DropEmptyState: View {
    let isTargeted: Bool
    var emptyText = "暂无任务"

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "tray")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(isTargeted ? YiRiTheme.accent : Color.secondary)
            Text(isTargeted ? "松开卡片" : emptyText)
                .font(.caption)
                .foregroundStyle(isTargeted ? YiRiTheme.accent : Color.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .background(YiRiTheme.panel.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct CompletedHistorySheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingTask: TaskItem?

    private var tasks: [TaskItem] {
        store.earlierCompleted()
    }

    private var groups: [CompletedDayGroup] {
        let grouped = Dictionary(grouping: tasks) { task in
            task.completedAt?.startOfLocalDay
        }
        return grouped
            .map { CompletedDayGroup(day: $0.key, tasks: $0.value) }
            .sorted { ($0.day ?? .distantPast) > ($1.day ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("之前已完成")
                        .font(.system(size: 24, weight: .medium))
                    Text("今天以前完成的全部任务，共 \(tasks.count) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(22)

            Divider()

            if tasks.isEmpty {
                EmptyState(
                    systemImage: "clock.arrow.circlepath",
                    title: "还没有历史成果",
                    detail: "今天以前完成的任务会保存在这里。"
                )
                .padding(22)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Text(group.title)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(group.tasks.count) 项")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }

                                ForEach(group.tasks) { task in
                                    CompletedTaskCard(
                                        task: task,
                                        highlighted: false,
                                        onEdit: { editingTask = task },
                                        onRestore: {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                store.setCompleted(task.id, completed: false)
                                            }
                                        },
                                        onDelete: {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                store.deleteTask(task.id)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(22)
                }
            }
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 500, idealHeight: 650)
        .background(YiRiTheme.page)
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(defaultDate: task.scheduledDate ?? Date(), task: task)
                .environmentObject(store)
        }
    }
}

private struct CompletedDayGroup: Identifiable {
    let day: Date?
    let tasks: [TaskItem]

    var id: String {
        day.map { String($0.timeIntervalSinceReferenceDate) } ?? "legacy"
    }

    var title: String {
        day.map { DateFormatter.yiRiDay.string(from: $0) } ?? "较早记录"
    }
}

private struct CompletedTaskCard: View {
    let task: TaskItem
    let highlighted: Bool
    let onEdit: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    private var completedTimeText: String {
        guard let completedAt = task.completedAt else { return "较早完成" }
        return "\(DateFormatter.yiRiTime.string(from: completedAt)) 完成"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 9) {
                ZStack {
                    Circle()
                        .fill(highlighted ? YiRiTheme.completionHighlight : YiRiTheme.completionSoft)
                        .frame(width: 24, height: 24)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(YiRiTheme.accent)
                }

                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                taskMenu
            }

            HStack(spacing: 7) {
                Text(task.category)
                    .font(.caption2)
                    .foregroundStyle(YiRiTheme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(YiRiTheme.completionSoft)
                    .clipShape(Capsule())
                Spacer()
            }

            HStack(spacing: 8) {
                Label(task.completionEffortText, systemImage: task.actualSeconds > 0 ? "timer" : "hand.tap")
                Spacer()
                Text(completedTimeText)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(
                colors: [YiRiTheme.panel, YiRiTheme.completionSoft.opacity(0.52)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(
                    highlighted ? YiRiTheme.completionHighlight : YiRiTheme.completionBorder,
                    lineWidth: highlighted ? 1.6 : 1
                )
        }
        .shadow(
            color: highlighted ? YiRiTheme.completionHighlight.opacity(0.34) : .clear,
            radius: highlighted ? 9 : 0,
            y: highlighted ? 3 : 0
        )
        .scaleEffect(highlighted ? 1.012 : 1)
        .animation(.easeOut(duration: 0.24), value: highlighted)
        .contextMenu {
            Button("编辑任务") { onEdit() }
            Button("恢复为未完成") { onRestore() }
            Divider()
            Button("删除任务", role: .destructive) { onDelete() }
        }
    }

    private var taskMenu: some View {
        Menu {
            Button("编辑") { onEdit() }
            Button("恢复为未完成") { onRestore() }
            Divider()
            Button("删除", role: .destructive) { onDelete() }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 28)
        .accessibilityLabel("任务操作")
    }
}

private struct CountBadge: View {
    let count: Int
    var completed = false

    var body: some View {
        Text("\(count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(completed ? YiRiTheme.accent : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(completed ? YiRiTheme.completionSoft : YiRiTheme.secondaryPanel)
            .clipShape(Capsule())
    }
}

private struct BoardTaskCard: View {
    @EnvironmentObject private var store: AppStore
    let task: TaskItem
    let accent: Bool
    let onEdit: () -> Void
    let onComplete: () -> Void

    private var scheduleText: String {
        guard let date = task.scheduledDate else { return "待安排" }
        return DateFormatter.yiRiSidebarDate.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(task.category)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(YiRiTheme.secondaryPanel)
                    .clipShape(Capsule())
                Spacer()
                taskMenu
            }
            Text(task.title)
                .font(.subheadline.weight(.medium))
            HStack {
                Text("预计 \(task.estimatedMinutes.durationText)")
                Spacer()
                Text(scheduleText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(YiRiTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(alignment: .leading) {
            if accent {
                RoundedRectangle(cornerRadius: 2)
                    .fill(YiRiTheme.accent)
                    .frame(width: 3)
                    .padding(.vertical, 7)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(accent ? YiRiTheme.accent.opacity(0.55) : YiRiTheme.border.opacity(0.55), lineWidth: 1)
        }
        .contextMenu {
            Button("编辑任务") { onEdit() }
            Button("标记完成") { onComplete() }
            Divider()
            Button("安排到今天") { store.moveTask(task.id, to: Date()) }
            Button("安排到明天") { store.moveTask(task.id, to: Date().addingDays(1)) }
            Divider()
            Button("删除任务", role: .destructive) { store.deleteTask(task.id) }
        }
        .draggable(task.id.uuidString)
        .accessibilityHint("可拖动到昨天、今天待完成或今天已完成")
    }

    private var taskMenu: some View {
        Menu {
            Button("编辑") { onEdit() }
            Divider()
            Button("安排到今天") { store.moveTask(task.id, to: Date()) }
            Button("安排到明天") { store.moveTask(task.id, to: Date().addingDays(1)) }
            Button("标记完成") { onComplete() }
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
        .accessibilityLabel("任务操作")
    }
}
