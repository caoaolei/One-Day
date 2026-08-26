import SwiftUI

struct TemplatesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingNewTemplate = false
    @State private var editingTemplate: TaskTemplate?

    private let columns = [GridItem(.adaptive(minimum: 250), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("重复使用你的工作方式")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("模版与提醒")
                            .font(.system(size: 28, weight: .medium))
                    }
                    Spacer()
                    Button {
                        showingNewTemplate = true
                    } label: {
                        Label("新建模版", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                ReminderSettingsView()
                WorktimeSettingsPanel()

                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(store.templates) { template in
                        TemplateCard(template: template) {
                            editingTemplate = template
                        }
                    }
                }
            }
            .yiRiPage()
        }
        .sheet(isPresented: $showingNewTemplate) {
            TemplateEditorSheet(template: nil)
                .environmentObject(store)
        }
        .sheet(item: $editingTemplate) { template in
            TemplateEditorSheet(template: template)
                .environmentObject(store)
        }
    }
}

struct WorktimeSettingsPanel: View {
    @EnvironmentObject private var worktime: WorktimeController
    @State private var isEnabled = false
    @State private var launchAtLogin = false
    @State private var pollingMinutes = 1
    @State private var workdayBoundaryMinutes = 6 * 60
    @State private var dailyTargetMinutes = 8 * 60
    @State private var message = ""

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("自动工时", systemImage: "briefcase.badge.clock")
                        .font(.headline)
                    Spacer()
                    Text(isEnabled ? "已开启" : "未开启")
                        .font(.caption)
                        .foregroundStyle(isEnabled ? YiRiTheme.accent : Color.secondary)
                }

                Toggle("自动记录每天最早和最晚键鼠活动", isOn: $isEnabled)
                    .toggleStyle(.switch)

                HStack(spacing: 18) {
                    Picker("检测间隔", selection: $pollingMinutes) {
                        Text("1 分钟").tag(1)
                        Text("2 分钟").tag(2)
                        Text("5 分钟").tag(5)
                        Text("10 分钟").tag(10)
                    }
                    Picker("凌晨归属", selection: $workdayBoundaryMinutes) {
                        Text("04:00 前归前一天").tag(4 * 60)
                        Text("05:00 前归前一天").tag(5 * 60)
                        Text("06:00 前归前一天").tag(6 * 60)
                    }
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("每日目标工时")
                            .font(.subheadline.weight(.medium))
                        Text("用于计算预计下班时间")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Button {
                            dailyTargetMinutes = max(60, dailyTargetMinutes - 30)
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.borderless)
                        .disabled(dailyTargetMinutes <= 60)

                        Text(dailyTargetText)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .frame(width: 92, alignment: .center)

                        Button {
                            dailyTargetMinutes = min(16 * 60, dailyTargetMinutes + 30)
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.borderless)
                        .disabled(dailyTargetMinutes >= 16 * 60)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(YiRiTheme.secondaryPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(YiRiTheme.border.opacity(0.7), lineWidth: 1)
                    }
                }

                HStack {
                    Toggle("登录 Mac 后自动启动一日", isOn: $launchAtLogin)
                        .toggleStyle(.checkbox)
                    Spacer()
                    Button("保存工时设置") { save() }
                        .buttonStyle(.borderedProminent)
                }

                Text(message.isEmpty ? "工时 = 最晚活动时间 − 最早活动时间，午休与中间离开也会计入。" : message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        let settings = worktime.settings
        isEnabled = settings.isEnabled
        launchAtLogin = settings.launchAtLogin
        pollingMinutes = settings.pollingMinutes
        workdayBoundaryMinutes = settings.workdayBoundaryMinutes
        dailyTargetMinutes = settings.dailyTargetMinutes
    }

    private func save() {
        let oldLaunchAtLogin = worktime.settings.launchAtLogin
        var settings = worktime.settings
        settings.isEnabled = isEnabled
        settings.pollingMinutes = max(1, pollingMinutes)
        settings.workdayBoundaryMinutes = workdayBoundaryMinutes
        settings.dailyTargetMinutes = dailyTargetMinutes
        worktime.updateSettings(settings)
        if launchAtLogin != oldLaunchAtLogin {
            worktime.setLaunchAtLogin(launchAtLogin)
        }
        load()
        message = worktime.launchAtLoginMessage ?? "工时设置已保存"
        if isEnabled {
            Task {
                let granted = await NotificationManager.shared.requestAuthorization()
                if granted {
                    worktime.refreshTargetNotification()
                    message = "工时设置已保存，预计下班提醒已开启"
                } else {
                    message = "设置已保存；请在系统设置中允许通知，以接收下班提醒"
                }
            }
        }
    }

    private var dailyTargetText: String {
        let hours = dailyTargetMinutes / 60
        let minutes = dailyTargetMinutes % 60
        return minutes == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes) 分"
    }
}

struct ReminderSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var morning = Date()
    @State private var evening = Date()
    @State private var policy = CarryOverPolicy.manual
    @State private var remindDoNotDisturb = true
    @State private var saving = false
    @State private var notificationMessage = ""

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("每日提醒", systemImage: "bell.badge")
                        .font(.headline)
                    Spacer()
                    Text(store.settings.notificationsAuthorized ? "通知已授权" : "需要通知权限")
                        .font(.caption)
                        .foregroundStyle(store.settings.notificationsAuthorized ? YiRiTheme.accent : .secondary)
                }

                HStack(spacing: 18) {
                    DatePicker("开始计划", selection: $morning, displayedComponents: .hourAndMinute)
                    DatePicker("晚间复盘", selection: $evening, displayedComponents: .hourAndMinute)
                    Picker("未完成任务", selection: $policy) {
                        ForEach(CarryOverPolicy.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .frame(minWidth: 190)
                }

                HStack {
                    Toggle("开始任务时提醒开启勿扰模式", isOn: $remindDoNotDisturb)
                        .toggleStyle(.checkbox)
                    Spacer()
                    Button(saving ? "正在保存…" : "授权并保存提醒") {
                        saveSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saving)
                }
                if !notificationMessage.isEmpty {
                    Label(
                        notificationMessage,
                        systemImage: store.settings.notificationsAuthorized ? "checkmark.circle" : "exclamationmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(store.settings.notificationsAuthorized ? YiRiTheme.accent : .secondary)
                }
            }
        }
        .onAppear {
            loadSettings()
            refreshAuthorizationStatus()
        }
    }

    private func loadSettings() {
        morning = Self.date(minutes: store.settings.morningReminderMinutes)
        evening = Self.date(minutes: store.settings.eveningReminderMinutes)
        policy = store.settings.carryOverPolicy
        remindDoNotDisturb = store.settings.remindDoNotDisturb
    }

    private func saveSettings() {
        var settings = store.settings
        settings.morningReminderMinutes = Self.minutes(from: morning)
        settings.eveningReminderMinutes = Self.minutes(from: evening)
        settings.carryOverPolicy = policy
        settings.remindDoNotDisturb = remindDoNotDisturb
        store.updateSettings(settings)
        saving = true
        Task {
            let granted = await NotificationManager.shared.requestAndSchedule(settings: settings)
            store.setNotificationAuthorization(granted)
            notificationMessage = granted
                ? "提醒已保存"
                : "通知未授权，请在“系统设置 → 通知 → 一日”中开启"
            saving = false
        }
    }

    private func refreshAuthorizationStatus() {
        Task {
            let authorized = await NotificationManager.shared.isAuthorized()
            store.setNotificationAuthorization(authorized)
        }
    }

    private static func date(minutes: Int) -> Date {
        Calendar.yiRi.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    private static func minutes(from date: Date) -> Int {
        let components = Calendar.yiRi.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

private struct TemplateCard: View {
    @EnvironmentObject private var store: AppStore
    let template: TaskTemplate
    let edit: () -> Void

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: template.isBuiltIn ? "sunrise.fill" : "square.grid.2x2.fill")
                        .font(.title2)
                        .foregroundStyle(YiRiTheme.accent)
                    Spacer()
                    if template.isBuiltIn {
                        Text("默认")
                            .font(.caption2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(YiRiTheme.accentSoft)
                            .clipShape(Capsule())
                    }
                    Menu {
                        Button("编辑") { edit() }
                        if !template.isBuiltIn {
                            Button("删除", role: .destructive) { store.deleteTemplate(template.id) }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 28)
                }
                Text(template.name)
                    .font(.headline)
                Text(template.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                ForEach(template.tasks.prefix(4)) { item in
                    HStack {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.title)
                            .font(.subheadline)
                        Spacer()
                        Text(item.estimatedMinutes.durationText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("编辑模版", action: edit)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

private struct TemplateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let template: TaskTemplate?

    @State private var name: String
    @State private var detail: String
    @State private var taskText: String
    @State private var defaultMinutes: Int

    init(template: TaskTemplate?) {
        self.template = template
        _name = State(initialValue: template?.name ?? "")
        _detail = State(initialValue: template?.detail ?? "")
        _taskText = State(initialValue: template?.tasks.map(\.title).joined(separator: "\n") ?? "")
        _defaultMinutes = State(initialValue: template?.tasks.first?.estimatedMinutes ?? 30)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(template == nil ? "新建模版" : "编辑模版")
                    .font(.title2.weight(.medium))
                Text("每行填写一个任务，应用模版时可以再次选择")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Form {
                TextField("模版名称", text: $name)
                TextField("说明", text: $detail)
                Stepper("默认估时 \(defaultMinutes.durationText)", value: $defaultMinutes, in: 5...240, step: 5)
                VStack(alignment: .leading, spacing: 6) {
                    Text("任务列表")
                    TextEditor(text: $taskText)
                        .frame(minHeight: 150)
                        .padding(7)
                        .scrollContentBackground(.hidden)
                        .background(YiRiTheme.inputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(YiRiTheme.border, lineWidth: 1)
                        }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存模版") {
                    let lines = taskText.components(separatedBy: .newlines)
                    if var template {
                        template.name = name
                        template.detail = detail
                        template.tasks = lines
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .map { TemplateTask(title: $0, category: "自定义", estimatedMinutes: defaultMinutes) }
                        store.updateTemplate(template)
                    } else {
                        store.addTemplate(name: name, detail: detail, taskLines: lines, defaultMinutes: defaultMinutes)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 600, height: 560)
    }
}
