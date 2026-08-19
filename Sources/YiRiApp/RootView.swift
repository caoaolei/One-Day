import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: AppSection? = .today
    @State private var showingProfileSetup = false

    private var displayName: String {
        let name = store.settings.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "设置称呼" : name
    }

    private var avatarText: String {
        guard displayName != "设置称呼", let first = displayName.first else { return "?" }
        return String(first).uppercased()
    }

    private var needsProfileSetup: Bool {
        store.settings.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(YiRiTheme.accent)
                    Text("一日")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)

                TimelineView(.periodic(from: .now, by: 60)) { context in
                    List(AppSection.allCases, selection: $selection) { section in
                        Label {
                            Text(section == .today ? "今天 · \(DateFormatter.yiRiSidebarDate.string(from: context.date))" : section.rawValue)
                        } icon: {
                            Image(systemName: section.systemImage)
                        }
                        .tag(section)
                        .padding(.vertical, 3)
                    }
                    .listStyle(.sidebar)
                }

                Button {
                    showingProfileSetup = true
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(YiRiTheme.warm)
                            .frame(width: 30, height: 30)
                            .overlay(Text(avatarText).foregroundStyle(.primary))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(displayName)
                                .font(.subheadline)
                            Text("数据仅保存在本机")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 230)
        } detail: {
            switch selection ?? .today {
            case .today:
                TodayView()
            case .board:
                BoardView()
            case .review:
                ReviewView()
            case .templates:
                TemplatesView()
            }
        }
        .sheet(isPresented: $showingProfileSetup) {
            ProfileSetupSheet(
                currentName: store.settings.displayName,
                isFirstLaunch: needsProfileSetup
            )
        }
        .onAppear {
            if needsProfileSetup, store.persistenceIssue == nil {
                showingProfileSetup = true
            }
        }
        .onChange(of: store.persistenceIssue) { issue in
            if issue == nil, needsProfileSetup {
                showingProfileSetup = true
            }
        }
        .alert(
            store.persistenceIssue?.title ?? "数据提示",
            isPresented: Binding(
                get: { store.persistenceIssue != nil },
                set: { presented in
                    if !presented { store.clearPersistenceIssue() }
                }
            )
        ) {
            Button("知道了") { store.clearPersistenceIssue() }
        } message: {
            Text(store.persistenceIssue?.message ?? "")
        }
    }
}
