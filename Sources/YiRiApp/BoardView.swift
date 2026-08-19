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
        store.completedTasks().count
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
                Text("查看全部成果")
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
        .help(historyCount == 0 ? "还没有完成的任务" : "查看包含今天在内的全部完成记录")
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
    @State private var mode: HistoryArchiveMode = .date
    @State private var editingTask: TaskItem?
    @State private var expandedTopicIDs: Set<String> = []
    @State private var nameAction: HistoryNameAction?
    @State private var selectionAction: HistorySelectionAction?

    private var tasks: [TaskItem] {
        store.completedTasks()
    }

    private var dayGroups: [HistoryDayGroup] {
        store.completedDayGroups()
    }

    private var topics: [HistoryTopic] {
        store.historyTopics()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("成果档案")
                        .font(.system(size: 24, weight: .medium))
                    Text("记录今天与过去完成的全部事情，共 \(tasks.count) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(22)

            Picker("成果浏览方式", selection: $mode) {
                ForEach(HistoryArchiveMode.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 22)
            .padding(.bottom, 16)

            Divider()

            if tasks.isEmpty {
                EmptyState(
                    systemImage: "clock.arrow.circlepath",
                    title: "还没有成果记录",
                    detail: "完成任务后，它会出现在日期和事项档案中。"
                )
                .padding(22)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        switch mode {
                        case .date:
                            ForEach(dayGroups) { group in
                                HistoryDaySection(
                                    group: group,
                                    onEdit: { editingTask = $0 },
                                    onRestore: restore,
                                    onDelete: delete
                                )
                            }
                        case .topic:
                            ForEach(topics) { topic in
                                HistoryTopicCard(
                                    topic: topic,
                                    isExpanded: expandedTopicIDs.contains(topic.id),
                                    onToggle: { toggleTopic(topic.id) },
                                    onRename: { nameAction = .rename(topic) },
                                    onMerge: { selectionAction = .merge(topic) },
                                    onEdit: { editingTask = $0 },
                                    onMove: { task in
                                        selectionAction = .move(task: task, sourceTopicID: topic.id)
                                    },
                                    onSplit: { nameAction = .split($0) },
                                    onRestore: restore,
                                    onDelete: delete
                                )
                            }
                        }
                    }
                    .padding(22)
                }
            }
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 540, idealHeight: 700)
        .background(YiRiTheme.page)
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(defaultDate: task.scheduledDate ?? Date(), task: task)
                .environmentObject(store)
        }
        .sheet(item: $nameAction) { action in
            HistoryNameSheet(action: action) { name in
                switch action {
                case let .rename(topic):
                    store.renameHistoryTopic(topic, to: name)
                case let .split(task):
                    store.splitHistoryTask(task.id, newTopicName: name)
                }
            }
        }
        .sheet(item: $selectionAction) { action in
            HistoryTopicPickerSheet(
                action: action,
                candidates: action.candidates(from: topics)
            ) { target in
                switch action {
                case let .move(task, _):
                    store.moveHistoryTask(task.id, to: target)
                case let .merge(source):
                    store.mergeHistoryTopic(source, into: target)
                }
            }
        }
    }

    private func toggleTopic(_ topicID: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedTopicIDs.contains(topicID) {
                expandedTopicIDs.remove(topicID)
            } else {
                expandedTopicIDs.insert(topicID)
            }
        }
    }

    private func restore(_ task: TaskItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            store.setCompleted(task.id, completed: false)
        }
    }

    private func delete(_ task: TaskItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            store.deleteTask(task.id)
        }
    }
}

private enum HistoryArchiveMode: String, CaseIterable, Identifiable {
    case date = "按日期"
    case topic = "按事项"

    var id: String { rawValue }
}

private struct HistoryDaySection: View {
    let group: HistoryDayGroup
    let onEdit: (TaskItem) -> Void
    let onRestore: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void

    private var title: String {
        guard let day = group.day else { return "较早记录" }
        if Calendar.yiRi.isDateInToday(day) {
            return "今天 · \(DateFormatter.yiRiDay.string(from: day))"
        }
        return DateFormatter.yiRiDay.string(from: day)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(group.tasks.count) 项")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if group.totalActualSeconds > 0 {
                    Label(historyDurationText(group.totalActualSeconds), systemImage: "timer")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if group.manualCompletionCount > 0 {
                    Text("\(group.manualCompletionCount) 项手动")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(group.tasks) { task in
                CompletedTaskCard(
                    task: task,
                    highlighted: false,
                    onEdit: { onEdit(task) },
                    onRestore: { onRestore(task) },
                    onDelete: { onDelete(task) }
                )
            }
        }
    }
}

private struct HistoryTopicCard: View {
    let topic: HistoryTopic
    let isExpanded: Bool
    let onToggle: () -> Void
    let onRename: () -> Void
    let onMerge: () -> Void
    let onEdit: (TaskItem) -> Void
    let onMove: (TaskItem) -> Void
    let onSplit: (TaskItem) -> Void
    let onRestore: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void

    private var dateRangeText: String {
        guard let first = topic.firstCompletedAt, let latest = topic.latestCompletedAt else {
            return "较早记录"
        }
        let firstText = DateFormatter.yiRiSidebarDate.string(from: first)
        let latestText = DateFormatter.yiRiSidebarDate.string(from: latest)
        return Calendar.yiRi.isDate(first, inSameDayAs: latest)
            ? latestText
            : "\(firstText) – \(latestText)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(YiRiTheme.completionSoft)
                        .frame(width: 38, height: 38)
                    Image(systemName: "checkmark.seal")
                        .foregroundStyle(YiRiTheme.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(topic.name)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(dateRangeText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Menu {
                    Button("重命名事项", systemImage: "pencil") { onRename() }
                    Button("合并到其他事项", systemImage: "arrow.triangle.merge") { onMerge() }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 30)
            }

            HStack(spacing: 10) {
                HistoryMetric(value: "\(topic.tasks.count)", label: "完成次数")
                HistoryMetric(
                    value: topic.totalActualSeconds > 0 ? historyDurationText(topic.totalActualSeconds) : "未计时",
                    label: "实际专注"
                )
                if topic.manualCompletionCount > 0 {
                    HistoryMetric(value: "\(topic.manualCompletionCount)", label: "手动完成")
                }
            }

            Button {
                onToggle()
            } label: {
                HStack {
                    Text(isExpanded ? "收起完成记录" : "展开完成记录")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(YiRiTheme.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(topic.tasks) { task in
                        CompletedTaskCard(
                            task: task,
                            highlighted: false,
                            onEdit: { onEdit(task) },
                            onRestore: { onRestore(task) },
                            onDelete: { onDelete(task) },
                            onMoveToTopic: { onMove(task) },
                            onSplitTopic: { onSplit(task) },
                            showsCompletionDate: true
                        )
                    }
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(YiRiTheme.completionBorder)
                        .frame(width: 2)
                        .padding(.vertical, 8)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(YiRiTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(YiRiTheme.completionBorder.opacity(0.8), lineWidth: 1)
        }
    }
}

private struct HistoryMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(YiRiTheme.completionSoft.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private enum HistoryNameAction: Identifiable {
    case rename(HistoryTopic)
    case split(TaskItem)

    var id: String {
        switch self {
        case let .rename(topic): "rename-\(topic.id)"
        case let .split(task): "split-\(task.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .rename: "重命名事项"
        case .split: "拆成新事项"
        }
    }

    var initialName: String {
        switch self {
        case let .rename(topic): topic.name
        case let .split(task): task.title
        }
    }
}

private struct HistoryNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let action: HistoryNameAction
    let onSave: (String) -> Void
    @State private var name: String

    init(action: HistoryNameAction, onSave: @escaping (String) -> Void) {
        self.action = action
        self.onSave = onSave
        _name = State(initialValue: action.initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(action.title)
                .font(.title3.weight(.semibold))
            TextField("事项名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 390)
        .background(YiRiTheme.page)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}

private enum HistorySelectionAction: Identifiable {
    case move(task: TaskItem, sourceTopicID: String)
    case merge(HistoryTopic)

    var id: String {
        switch self {
        case let .move(task, _): "move-\(task.id.uuidString)"
        case let .merge(topic): "merge-\(topic.id)"
        }
    }

    var title: String {
        switch self {
        case .move: "移入其他事项"
        case .merge: "合并事项"
        }
    }

    func candidates(from topics: [HistoryTopic]) -> [HistoryTopic] {
        switch self {
        case let .move(_, sourceTopicID):
            return topics.filter { $0.id != sourceTopicID }
        case let .merge(source):
            return topics.filter { $0.id != source.id }
        }
    }
}

private struct HistoryTopicPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let action: HistorySelectionAction
    let candidates: [HistoryTopic]
    let onSelect: (HistoryTopic) -> Void
    @State private var selectedID: String?

    init(
        action: HistorySelectionAction,
        candidates: [HistoryTopic],
        onSelect: @escaping (HistoryTopic) -> Void
    ) {
        self.action = action
        self.candidates = candidates
        self.onSelect = onSelect
        _selectedID = State(initialValue: candidates.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(action.title)
                .font(.title3.weight(.semibold))

            if candidates.isEmpty {
                Text("目前没有其他事项可供选择。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            } else {
                Picker("目标事项", selection: $selectedID) {
                    ForEach(candidates) { topic in
                        Text("\(topic.name) · \(topic.tasks.count) 次")
                            .tag(Optional(topic.id))
                    }
                }
                .pickerStyle(.radioGroup)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("确认") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedID == nil)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(YiRiTheme.page)
    }

    private func save() {
        guard let selectedID,
              let topic = candidates.first(where: { $0.id == selectedID }) else { return }
        onSelect(topic)
        dismiss()
    }
}

private struct CompletedTaskCard: View {
    let task: TaskItem
    let highlighted: Bool
    let onEdit: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void
    var onMoveToTopic: (() -> Void)? = nil
    var onSplitTopic: (() -> Void)? = nil
    var showsCompletionDate = false

    private var completedTimeText: String {
        guard let completedAt = task.completedAt else { return "较早完成" }
        if showsCompletionDate {
            return "\(DateFormatter.yiRiSidebarDate.string(from: completedAt)) \(DateFormatter.yiRiTime.string(from: completedAt)) 完成"
        }
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
            if let onMoveToTopic {
                Button("移入其他事项") { onMoveToTopic() }
            }
            if let onSplitTopic {
                Button("拆成新事项") { onSplitTopic() }
            }
            Divider()
            Button("删除任务", role: .destructive) { onDelete() }
        }
    }

    private var taskMenu: some View {
        Menu {
            Button("编辑") { onEdit() }
            Button("恢复为未完成") { onRestore() }
            if let onMoveToTopic {
                Button("移入其他事项") { onMoveToTopic() }
            }
            if let onSplitTopic {
                Button("拆成新事项") { onSplitTopic() }
            }
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

private func historyDurationText(_ seconds: Int) -> String {
    guard seconds > 0 else { return "未计时" }
    if seconds < 60 { return "< 1 分钟" }
    return seconds.secondsDurationText
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
