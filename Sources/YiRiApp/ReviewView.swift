import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var store: AppStore
    @State private var note = ""
    @State private var justSaved = false

    private var tasks: [TaskItem] { store.tasks(on: Date()) }
    private var completed: [TaskItem] { tasks.filter(\.isCompleted) }
    private var actualSeconds: Int { completed.reduce(0) { $0 + $1.actualSeconds } }
    private var estimatedSeconds: Int { completed.reduce(0) { $0 + $1.estimatedMinutes * 60 } }
    private var accuracy: Int {
        guard estimatedSeconds > 0 else { return 0 }
        let difference = abs(actualSeconds - estimatedSeconds)
        return max(0, Int((1 - Double(difference) / Double(estimatedSeconds)) * 100))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("晚间复盘 · 预计 3 分钟")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("今天过得怎么样？")
                            .font(.system(size: 28, weight: .medium))
                    }
                    Spacer()
                    if justSaved || store.review(on: Date()) != nil {
                        Label("已保存", systemImage: "checkmark.icloud")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Panel {
                    HStack(spacing: 28) {
                        StatView(value: "\(completed.count) / \(tasks.count)", label: "完成任务")
                        Divider().frame(height: 44)
                        StatView(value: actualSeconds.secondsDurationText, label: "实际专注")
                        Divider().frame(height: 44)
                        StatView(value: "\(accuracy)%", label: "估时准确度")
                    }
                }

                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionHeader(title: "确认任务状态", subtitle: "未完成任务默认由你逐项决定")
                            Spacer()
                            Picker("处理方式", selection: Binding(
                                get: { store.settings.carryOverPolicy },
                                set: { value in
                                    var settings = store.settings
                                    settings.carryOverPolicy = value
                                    store.updateSettings(settings)
                                }
                            )) {
                                ForEach(CarryOverPolicy.allCases) { policy in
                                    Text(policy.rawValue).tag(policy)
                                }
                            }
                            .frame(width: 190)
                        }
                        Divider()
                        if tasks.isEmpty {
                            EmptyState(systemImage: "moon.stars", title: "今天没有任务", detail: "仍然可以写一段复盘备注。")
                        } else {
                            ForEach(tasks) { task in
                                HStack(spacing: 10) {
                                    Toggle("", isOn: Binding(
                                        get: { task.isCompleted },
                                        set: { store.setCompleted(task.id, completed: $0) }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
                                    Text(task.title)
                                        .strikethrough(task.isCompleted)
                                    Spacer()
                                    Text("预计 \(task.estimatedMinutes.durationText)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !task.isCompleted {
                                        Button("移到明天") { store.moveTask(task.id, to: Date().addingDays(1)) }
                                            .buttonStyle(.bordered)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                }

                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("今天值得记住什么？")
                                .font(.headline)
                            Text("可选")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        TextEditor(text: $note)
                            .font(.body)
                            .frame(minHeight: 120)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(YiRiTheme.secondaryPanel)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        HStack {
                            Text("完成得好的、遇到的阻碍、明天想调整的……")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("完成今日复盘") {
                                store.saveReview(note: note)
                                justSaved = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .yiRiPage()
        }
        .onAppear {
            note = store.review(on: Date())?.note ?? ""
        }
    }
}
