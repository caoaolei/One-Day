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

struct ReminderSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var morning = Date()
    @State private var evening = Date()
    @State private var policy = CarryOverPolicy.manual
    @State private var remindDoNotDisturb = true
    @State private var saving = false

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
            }
        }
        .onAppear { loadSettings() }
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
            saving = false
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
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
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
                        .background(YiRiTheme.secondaryPanel)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
