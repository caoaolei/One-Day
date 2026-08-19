import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var store: AppStore
    @State private var note = ""
    @State private var justSaved = false
    @State private var completionSummary: ReviewCompletionSummary?

    private var tasks: [TaskItem] { store.tasks(on: Date()) }
    private var completed: [TaskItem] { tasks.filter(\.isCompleted) }
    private var timedCompleted: [TaskItem] { completed.filter { $0.actualSeconds > 0 } }
    private var actualSeconds: Int { timedCompleted.reduce(0) { $0 + $1.actualSeconds } }
    private var estimatedSeconds: Int { timedCompleted.reduce(0) { $0 + $1.estimatedMinutes * 60 } }
    private var accuracy: Int? {
        guard estimatedSeconds > 0 else { return nil }
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
                        StatView(value: accuracy.map { "\($0)%" } ?? "—", label: "估时准确度")
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
                            .background(YiRiTheme.inputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(YiRiTheme.border, lineWidth: 1)
                            }
                        HStack {
                            Text("完成得好的、遇到的阻碍、明天想调整的……")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("完成今日复盘") {
                                let summary = ReviewCompletionSummary(
                                    displayName: store.settings.displayName,
                                    completedCount: completed.count,
                                    totalCount: tasks.count,
                                    focusedSeconds: actualSeconds,
                                    hasNote: !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                )
                                store.saveReview(note: note)
                                justSaved = true
                                completionSummary = summary
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
        .sheet(item: $completionSummary) { summary in
            ReviewCompletionSheet(summary: summary)
        }
    }
}

private struct ReviewCompletionSummary: Identifiable {
    let id = UUID()
    let displayName: String?
    let completedCount: Int
    let totalCount: Int
    let focusedSeconds: Int
    let hasNote: Bool

    var trimmedDisplayName: String {
        displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var eyebrow: String {
        trimmedDisplayName.isEmpty ? "今天辛苦了" : "\(trimmedDisplayName)，今天辛苦了"
    }

    var title: String {
        if totalCount > 0, completedCount == totalCount { return "今天圆满收官" }
        if completedCount > 0 { return "今天又向前了一步" }
        if hasNote { return "谢谢你认真回望今天" }
        return "先把今天轻轻放下"
    }

    var message: String {
        if totalCount > 0, completedCount == totalCount {
            return "所有计划都完成了，做得很好。现在可以安心休息了。"
        }
        if completedCount > 0 {
            return "完成的每一件小事都算数。未完成的留给明天，今晚好好休息。"
        }
        if hasNote {
            return "愿意停下来复盘，本身就是在为明天积蓄力量。"
        }
        return "不是每一天都要满载而归。保存今天，然后轻松一点。"
    }

    var symbol: String {
        totalCount > 0 && completedCount == totalCount ? "checkmark.seal.fill" : "moon.stars.fill"
    }
}

private struct ReviewCompletionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let summary: ReviewCompletionSummary
    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [YiRiTheme.panel, YiRiTheme.accentSoft.opacity(0.72), YiRiTheme.warm.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(YiRiTheme.accent.opacity(0.08))
                .frame(width: 230, height: 230)
                .blur(radius: 20)
                .offset(x: 210, y: -150)

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(YiRiTheme.panel.opacity(0.92))
                        .frame(width: 92, height: 92)
                        .shadow(color: YiRiTheme.accent.opacity(0.15), radius: 24, y: 8)
                    Circle()
                        .stroke(YiRiTheme.accent.opacity(0.18), lineWidth: 1)
                        .frame(width: 74, height: 74)
                    Image(systemName: summary.symbol)
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(YiRiTheme.accent)
                    Image(systemName: "sparkle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(YiRiTheme.accent)
                        .offset(x: 48, y: -36)
                }
                .scaleEffect(appeared ? 1 : 0.78)
                .opacity(appeared ? 1 : 0)

                VStack(spacing: 8) {
                    Text(summary.eyebrow)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(YiRiTheme.accent)
                    Text(summary.title)
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                    Text(summary.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 380)
                }
                .offset(y: appeared ? 0 : 8)
                .opacity(appeared ? 1 : 0)

                HStack(spacing: 12) {
                    ReviewCompletionStat(
                        value: "\(summary.completedCount) / \(summary.totalCount)",
                        label: "完成任务",
                        systemImage: "checkmark.circle"
                    )
                    ReviewCompletionStat(
                        value: summary.focusedSeconds.secondsDurationText,
                        label: "专注时间",
                        systemImage: "timer"
                    )
                }
                .frame(maxWidth: 390)
                .offset(y: appeared ? 0 : 10)
                .opacity(appeared ? 1 : 0)

                Button("好，结束今天") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(34)
        }
        .frame(width: 520, height: 440)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                appeared = true
            }
        }
    }
}

private struct ReviewCompletionStat: View {
    let value: String
    let label: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(YiRiTheme.accent)
                .frame(width: 28, height: 28)
                .background(YiRiTheme.accentSoft)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(YiRiTheme.panel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(YiRiTheme.border.opacity(0.65), lineWidth: 1)
        }
    }
}
