import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingTaskEditor = false
    @State private var showingMeetingEditor = false
    @State private var showingBatchAdd = false

    private var todayTasks: [TaskItem] { store.tasks(on: Date()) }
    private var todayMeetings: [MeetingItem] { store.meetings(on: Date()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageHeader

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
        .sheet(isPresented: $showingTaskEditor) {
            TaskEditorSheet(defaultDate: Date())
                .environmentObject(store)
        }
        .sheet(isPresented: $showingMeetingEditor) {
            MeetingEditorSheet(defaultDate: Date())
                .environmentObject(store)
        }
        .sheet(isPresented: $showingBatchAdd) {
            BatchAddSheet()
                .environmentObject(store)
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(DateFormatter.yiRiDay.string(from: Date()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("早上好，今天想完成什么？")
                    .font(.system(size: 28, weight: .medium))
            }
            Spacer()
            Button {
                showingBatchAdd = true
            } label: {
                Label("批量补录", systemImage: "calendar.badge.plus")
            }
            Button {
                showingTaskEditor = true
            } label: {
                Label("添加任务", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
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
                            TodayTaskRow(task: task)
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

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { task.isCompleted },
                set: { store.setCompleted(task.id, completed: $0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
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
                Button("移到明天") { store.moveTask(task.id, to: Date().addingDays(1)) }
                Button("放回待安排") { store.moveTask(task.id, to: nil) }
                Divider()
                Button("删除", role: .destructive) { store.deleteTask(task.id) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.vertical, 10)
    }
}
