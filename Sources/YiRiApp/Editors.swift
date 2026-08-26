import SwiftUI

struct ProfileSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    let isFirstLaunch: Bool
    @State private var name: String

    init(currentName: String?, isFirstLaunch: Bool) {
        self.isFirstLaunch = isFirstLaunch
        _name = State(initialValue: currentName ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "sunrise.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(YiRiTheme.accent)
                    .frame(width: 54, height: 54)
                    .background(YiRiTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                sheetHeader(
                    title: isFirstLaunch ? "欢迎使用一日" : "修改个人称呼",
                    subtitle: isFirstLaunch ? "先告诉我怎么称呼你，信息只保存在这台 Mac" : "新的称呼会显示在侧边栏"
                )
            }

            TextField("你的称呼", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .onSubmit(save)

            HStack {
                if !isFirstLaunch {
                    Button("取消") { dismiss() }
                }
                Spacer()
                Button(isFirstLaunch ? "开始使用" : "保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(28)
        .frame(width: 460, height: 250)
        .interactiveDismissDisabled(isFirstLaunch)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        store.updateDisplayName(trimmedName)
        dismiss()
    }
}

struct TaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    let defaultDate: Date
    let task: TaskItem?
    @State private var title: String
    @State private var category: String
    @State private var estimatedMinutes: Int
    @State private var scheduledDate: Date
    @State private var scheduleMode: TaskScheduleMode
    @State private var workdayCount = 5
    @State private var skipDuplicates = true
    @State private var suggestionReason = ""
    @FocusState private var focusedField: TaskEditorField?

    private let categories = ["深度工作", "日常", "写作", "规划", "复盘", "自定义"]

    init(defaultDate: Date, task: TaskItem? = nil) {
        self.defaultDate = defaultDate
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _category = State(initialValue: task?.category ?? "深度工作")
        _estimatedMinutes = State(initialValue: task?.estimatedMinutes ?? 45)
        _scheduledDate = State(initialValue: task?.scheduledDate ?? defaultDate)
        _scheduleMode = State(initialValue: .single)
    }

    private var futurePlan: FutureWorkdayPlan {
        store.futureWorkdayPlan(
            title: title,
            workdayCount: workdayCount,
            skipDuplicates: skipDuplicates
        )
    }

    private var submitTitle: String {
        if task != nil { return "保存修改" }
        if scheduleMode == .workdays { return "创建 \(futurePlan.creatableDates.count) 个任务" }
        if Calendar.yiRi.isDate(scheduledDate, inSameDayAs: Date()) { return "加入今天" }
        if Calendar.yiRi.isDate(scheduledDate, inSameDayAs: Date().addingDays(1)) { return "安排到明天" }
        return "创建未来任务"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            sheetHeader(title: task == nil ? "添加任务" : "编辑任务", subtitle: "自动估时会优先参考你过去的实际用时")

            Form {
                LabeledContent("任务名称") {
                    TextField("例如：整理项目方案", text: $title)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .title)
                        .font(.body)
                        .tint(YiRiTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(YiRiTheme.inputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    focusedField == .title ? YiRiTheme.accent : YiRiTheme.border,
                                    lineWidth: focusedField == .title ? 1.5 : 1
                                )
                        }
                        .frame(minWidth: 340)
                }
                Picker("分类", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                if task == nil {
                    Picker("安排方式", selection: $scheduleMode) {
                        ForEach(TaskScheduleMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if task != nil || scheduleMode == .single {
                    DatePicker("安排日期", selection: $scheduledDate, displayedComponents: .date)
                } else {
                    Stepper("连续 \(workdayCount) 个工作日", value: $workdayCount, in: 1...92)
                    Toggle("跳过同一日期的同名任务", isOn: $skipDuplicates)
                        .toggleStyle(.checkbox)

                    if let firstDate = futurePlan.dates.first, let lastDate = futurePlan.dates.last {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(
                                "\(DateFormatter.yiRiSidebarDate.string(from: firstDate)) 至 \(DateFormatter.yiRiSidebarDate.string(from: lastDate))",
                                systemImage: "calendar.badge.plus"
                            )
                            Text("将创建 \(futurePlan.creatableDates.count) 条任务" + (futurePlan.skippedDuplicateCount > 0 ? "，跳过 \(futurePlan.skippedDuplicateCount) 条重复" : ""))
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .foregroundStyle(YiRiTheme.accent)
                    }
                }
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
                Button(submitTitle) {
                    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if var task {
                        task.title = trimmedTitle
                        task.category = category
                        task.estimatedMinutes = estimatedMinutes
                        task.scheduledDate = scheduledDate.startOfLocalDay
                        store.updateTask(task)
                    } else if scheduleMode == .single {
                        store.addTask(
                            title: trimmedTitle,
                            category: category,
                            estimatedMinutes: estimatedMinutes,
                            date: scheduledDate
                        )
                    } else {
                        store.addFutureWorkdayTasks(
                            title: trimmedTitle,
                            category: category,
                            estimatedMinutes: estimatedMinutes,
                            workdayCount: workdayCount,
                            skipDuplicates: skipDuplicates
                        )
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (task == nil && scheduleMode == .workdays && futurePlan.creatableDates.isEmpty)
                )
            }
        }
        .padding(24)
        .frame(width: 580, height: task == nil ? 520 : 440)
        .onAppear {
            DispatchQueue.main.async {
                focusedField = .title
            }
        }
    }
}

private enum TaskEditorField: Hashable {
    case title
}

private enum TaskScheduleMode: String, CaseIterable, Identifiable {
    case single = "单日"
    case workdays = "连续工作日"

    var id: String { rawValue }
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
