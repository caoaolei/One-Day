import SwiftUI

struct BoardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingTaskEditor = false
    @State private var editingTask: TaskItem?

    private var overdue: [TaskItem] {
        store.overdueTasks()
    }

    private var today: [TaskItem] {
        store.tasks(on: Date()).filter { !$0.isCompleted }
    }

    private var completed: [TaskItem] {
        Array(store.tasks.filter(\.isCompleted).sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }.prefix(20))
    }

    private var unplannedOrUpcoming: [TaskItem] {
        store.unplannedOrUpcomingTasks()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("所有任务")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("任务看板")
                            .font(.system(size: 28, weight: .medium))
                    }
                    Spacer()
                    Button {
                        showingTaskEditor = true
                    } label: {
                        Label("新建任务", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(alignment: .top, spacing: 14) {
                    BoardColumn(
                        title: "昨天",
                        subtitle: "含更早未完成",
                        tasks: overdue,
                        accent: false,
                        onEdit: edit
                    )
                    BoardColumn(
                        title: "今天",
                        subtitle: "今日待完成",
                        tasks: today,
                        accent: true,
                        onEdit: edit
                    )
                    BoardColumn(
                        title: "已完成",
                        subtitle: "最近 20 条",
                        tasks: completed,
                        accent: false,
                        onEdit: edit
                    )
                }

                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            title: "待安排与未来",
                            subtitle: "放回待安排或安排到未来日期的任务都会保留在这里"
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
                                    BoardTaskCard(task: task, accent: false, onEdit: { edit(task) })
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
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(defaultDate: task.scheduledDate ?? Date(), task: task)
                .environmentObject(store)
        }
    }

    private func edit(_ task: TaskItem) {
        editingTask = task
    }
}

private struct BoardColumn: View {
    let title: String
    let subtitle: String
    let tasks: [TaskItem]
    let accent: Bool
    let onEdit: (TaskItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(tasks.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(YiRiTheme.secondaryPanel)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 3)

            if tasks.isEmpty {
                Text("暂无任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ForEach(tasks) { task in
                    BoardTaskCard(task: task, accent: accent, onEdit: { onEdit(task) })
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(YiRiTheme.secondaryPanel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(YiRiTheme.border.opacity(0.7), lineWidth: 1)
        }
    }
}

private struct BoardTaskCard: View {
    @EnvironmentObject private var store: AppStore
    let task: TaskItem
    let accent: Bool
    let onEdit: () -> Void

    private var scheduleText: String? {
        guard !task.isCompleted else { return nil }
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
                Menu {
                    Button("编辑") { onEdit() }
                    if !task.isCompleted {
                        Divider()
                        Button("安排到今天") { store.moveTask(task.id, to: Date()) }
                        Button("安排到明天") { store.moveTask(task.id, to: Date().addingDays(1)) }
                        Button("标记完成") { store.setCompleted(task.id, completed: true) }
                    }
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
            Text(task.title)
                .font(.subheadline.weight(.medium))
                .strikethrough(task.isCompleted)
            HStack {
                Text(task.isCompleted ? "实际 \(task.actualSeconds.secondsDurationText)" : "预计 \(task.estimatedMinutes.durationText)")
                Spacer()
                if let scheduleText {
                    Text(scheduleText)
                }
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
            if !task.isCompleted {
                Button("安排到今天") { store.moveTask(task.id, to: Date()) }
                Button("安排到明天") { store.moveTask(task.id, to: Date().addingDays(1)) }
            }
            Divider()
            Button("删除任务", role: .destructive) { store.deleteTask(task.id) }
        }
    }
}
