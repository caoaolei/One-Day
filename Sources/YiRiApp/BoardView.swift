import SwiftUI

struct BoardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingTaskEditor = false

    private var backlog: [TaskItem] {
        store.tasks.filter { !$0.isCompleted && ($0.scheduledDate == nil || !Calendar.yiRi.isDateInToday($0.scheduledDate!)) }
    }

    private var today: [TaskItem] {
        store.tasks.filter { item in
            !item.isCompleted && item.scheduledDate.map(Calendar.yiRi.isDateInToday) == true
        }
    }

    private var completed: [TaskItem] {
        Array(store.tasks.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }.prefix(20))
    }

    var body: some View {
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
                BoardColumn(title: "待安排", count: backlog.count, tasks: backlog, accent: false)
                BoardColumn(title: "今天", count: today.count, tasks: today, accent: true)
                BoardColumn(title: "已完成", count: completed.count, tasks: completed, accent: false)
            }
        }
        .yiRiPage()
        .sheet(isPresented: $showingTaskEditor) {
            TaskEditorSheet(defaultDate: Date())
                .environmentObject(store)
        }
    }
}

private struct BoardColumn: View {
    let title: String
    let count: Int
    let tasks: [TaskItem]
    let accent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(count)")
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
                    BoardTaskCard(task: task, accent: accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    if !task.isCompleted {
                        Button("安排到今天") { store.moveTask(task.id, to: Date()) }
                        Button("安排到明天") { store.moveTask(task.id, to: Date().addingDays(1)) }
                        Button("标记完成") { store.setCompleted(task.id, completed: true) }
                    }
                    Button("删除", role: .destructive) { store.deleteTask(task.id) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
            Text(task.title)
                .font(.subheadline.weight(.medium))
                .strikethrough(task.isCompleted)
            Text(task.isCompleted ? "实际 \(task.actualSeconds.secondsDurationText)" : "预计 \(task.estimatedMinutes.durationText)")
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
    }
}
