import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: AppSection? = .today

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

                List(AppSection.allCases, selection: $selection) { section in
                    Label(section.rawValue, systemImage: section.systemImage)
                        .tag(section)
                        .padding(.vertical, 3)
                }
                .listStyle(.sidebar)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(YiRiTheme.warm)
                            .frame(width: 30, height: 30)
                            .overlay(Text("C").foregroundStyle(.primary))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Cal")
                                .font(.subheadline)
                            Text("数据仅保存在本机")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                }
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
    }
}
