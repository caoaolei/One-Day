import SwiftUI

struct TaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    let defaultDate: Date
    let task: TaskItem?
    @State private var title: String
    @State private var category: String
    @State private var estimatedMinutes: Int
    @State private var scheduledDate: Date
    @State private var suggestionReason = ""

    private let categories = ["深度工作", "日常", "写作", "规划", "复盘", "自定义"]

    init(defaultDate: Date, task: TaskItem? = nil) {
        self.defaultDate = defaultDate
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _category = State(initialValue: task?.category ?? "深度工作")
        _estimatedMinutes = State(initialValue: task?.estimatedMinutes ?? 45)
        _scheduledDate = State(initialValue: task?.scheduledDate ?? defaultDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            sheetHeader(title: task == nil ? "添加任务" : "编辑任务", subtitle: "自动估时会优先参考你过去的实际用时")

            Form {
                TextField("任务名称", text: $title)
                Picker("分类", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                DatePicker("安排日期", selection: $scheduledDate, displayedComponents: .date)
                HStack {
                    Stepper("预计 \(estimatedMinutes.durationText)", value: $estimatedMinutes, in: 5...480, step: 5)
                    Spacer()
                    Button {
                        let suggestion = store.autoEstimate(title: title, category: category)
                        estimatedMinutes = suggestion.minutes
                        suggestionReason = suggestion.reason
                    } label: {
                        Label("自动估时", systemImage: "sparkles")
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !suggestionReason.isEmpty {
                    Label("建议 \(estimatedMinutes.durationText) · \(suggestionReason)，你仍可修改", systemImage: "wand.and.stars")
                        .font(.caption)
                        .foregroundStyle(YiRiTheme.accent)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button(task == nil ? "加入今天" : "保存修改") {
                    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if var task {
                        task.title = trimmedTitle
                        task.category = category
                        task.estimatedMinutes = estimatedMinutes
                        task.scheduledDate = scheduledDate.startOfLocalDay
                        store.updateTask(task)
                    } else {
                        store.addTask(
                            title: trimmedTitle,
                            category: category,
                            estimatedMinutes: estimatedMinutes,
                            date: scheduledDate
                        )
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560, height: 440)
    }
}

struct MeetingEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    let meeting: MeetingItem?
    @State private var title: String
    @State private var startDate: Date
    @State private var durationMinutes: Int
    @State private var location: String

    init(defaultDate: Date, meeting: MeetingItem? = nil) {
        let initial = Calendar.yiRi.date(bySettingHour: 10, minute: 0, second: 0, of: defaultDate) ?? defaultDate
        self.meeting = meeting
        _title = State(initialValue: meeting?.title ?? "")
        _startDate = State(initialValue: meeting?.startDate ?? initial)
        _durationMinutes = State(initialValue: meeting?.durationMinutes ?? 45)
        _location = State(initialValue: meeting?.location ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            sheetHeader(title: meeting == nil ? "添加会议" : "编辑会议", subtitle: "会议仅手动录入，不会连接外部日历")
            Form {
                TextField("会议名称", text: $title)
                DatePicker("开始时间", selection: $startDate)
                Stepper("时长 \(durationMinutes) 分钟", value: $durationMinutes, in: 5...480, step: 5)
                TextField("地点或会议链接", text: $location)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button(meeting == nil ? "添加会议" : "保存修改") {
                    if var meeting {
                        meeting.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        meeting.startDate = startDate
                        meeting.durationMinutes = durationMinutes
                        meeting.location = location
                        store.updateMeeting(meeting)
                    } else {
                        store.addMeeting(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            startDate: startDate,
                            durationMinutes: durationMinutes,
                            location: location
                        )
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 540, height: 390)
    }
}

struct BatchAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    @State private var startDate = Date().addingDays(-3)
    @State private var endDate = Date()
    @State private var selectedTemplateID: UUID?
    @State private var selectedTaskIDs: Set<UUID> = []
    @State private var skipDuplicates = true

    private var selectedTemplate: TaskTemplate? {
        if let selectedTemplateID {
            return store.templates.first(where: { $0.id == selectedTemplateID })
        }
        return store.templates.first
    }

    private var dayCount: Int {
        let start = startDate.startOfLocalDay
        let end = endDate.startOfLocalDay
        guard end >= start else { return 0 }
        return min(92, (Calendar.yiRi.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sheetHeader(title: "批量补每日任务", subtitle: "为一段日期补充模版任务，最多一次处理 92 天")

            HStack(spacing: 14) {
                DatePicker("开始", selection: $startDate, displayedComponents: .date)
                DatePicker("结束", selection: $endDate, in: startDate..., displayedComponents: .date)
                Picker("模版", selection: $selectedTemplateID) {
                    ForEach(store.templates) { template in
                        Text(template.name).tag(Optional(template.id))
                    }
                }
                .frame(minWidth: 180)
            }

            Panel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("选择要补录的任务")
                        .font(.headline)
                    if let template = selectedTemplate {
                        ForEach(template.tasks) { item in
                            Toggle(isOn: Binding(
                                get: { selectedTaskIDs.contains(item.id) },
                                set: { selected in
                                    if selected { selectedTaskIDs.insert(item.id) }
                                    else { selectedTaskIDs.remove(item.id) }
                                }
                            )) {
                                HStack {
                                    Text(item.title)
                                    Spacer()
                                    Text(item.estimatedMinutes.durationText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            Toggle("跳过已经有同名任务的日期", isOn: $skipDuplicates)
                .toggleStyle(.checkbox)

            Label("将为 \(dayCount) 天补录最多 \(dayCount * selectedTaskIDs.count) 条任务", systemImage: "calendar.badge.checkmark")
                .font(.subheadline)
                .foregroundStyle(YiRiTheme.accent)
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(YiRiTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("确认补录") {
                    guard let template = selectedTemplate else { return }
                    _ = store.batchAdd(
                        template: template,
                        startDate: startDate,
                        endDate: endDate,
                        selectedTaskIDs: selectedTaskIDs,
                        skipDuplicates: skipDuplicates
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(dayCount == 0 || selectedTaskIDs.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 700, height: 570)
        .onAppear {
            selectedTemplateID = selectedTemplateID ?? store.templates.first?.id
            selectedTaskIDs = Set(selectedTemplate?.tasks.map(\.id) ?? [])
        }
        .onChange(of: selectedTemplateID) { _ in
            selectedTaskIDs = Set(selectedTemplate?.tasks.map(\.id) ?? [])
        }
    }
}

@ViewBuilder
private func sheetHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.title2.weight(.medium))
        Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
