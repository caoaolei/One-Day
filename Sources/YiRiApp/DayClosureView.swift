import SwiftUI

enum DayClosureDestination {
    case today
    case review

    var eyebrow: String {
        switch self {
        case .today: "今天已收好"
        case .review: "今日复盘已完成"
        }
    }

    var title: String {
        switch self {
        case .today: "今天已经好好收尾"
        case .review: "该写下的，都已安静归档"
        }
    }

    var message: String {
        switch self {
        case .today:
            "今日计划与复盘已经封存。自动工时仍会继续，需要下班时请前往“工时”手动结束今天。"
        case .review:
            "复盘已经归档，不用再回头修改。自动工时仍独立记录，需要下班时请前往“工时”结束今天。"
        }
    }
}

struct DayClosureView: View {
    let destination: DayClosureDestination
    let date: Date
    let displayName: String?
    @State private var appeared = false

    private var greeting: String {
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? destination.title : "\(name)，\(destination.title)"
    }

    var body: some View {
        ZStack {
            YiRiTheme.page

            Circle()
                .fill(YiRiTheme.accentSoft.opacity(0.78))
                .frame(width: 520, height: 520)
                .blur(radius: 6)
                .offset(x: 280, y: -250)

            Circle()
                .fill(YiRiTheme.warm.opacity(0.50))
                .frame(width: 420, height: 420)
                .blur(radius: 18)
                .offset(x: -330, y: 270)

            VStack(spacing: 24) {
                Spacer(minLength: 36)

                ZStack {
                    Circle()
                        .fill(YiRiTheme.panel.opacity(0.88))
                        .frame(width: 154, height: 154)
                        .shadow(color: YiRiTheme.accent.opacity(0.14), radius: 32, y: 12)

                    Circle()
                        .stroke(YiRiTheme.completionBorder.opacity(0.7), lineWidth: 1)
                        .frame(width: 126, height: 126)

                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 54, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(YiRiTheme.accent)

                    Image(systemName: "sparkle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(YiRiTheme.accent)
                        .offset(x: 78, y: -58)

                    Image(systemName: "sparkle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(YiRiTheme.accent.opacity(0.72))
                        .offset(x: -76, y: 52)
                }
                .scaleEffect(appeared ? 1 : 0.88)
                .opacity(appeared ? 1 : 0)

                VStack(spacing: 10) {
                    Text(destination.eyebrow)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(YiRiTheme.accent)
                        .textCase(.uppercase)
                        .tracking(1.2)

                    Text(greeting)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text(destination.message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .frame(maxWidth: 500)
                }
                .offset(y: appeared ? 0 : 10)
                .opacity(appeared ? 1 : 0)

                Text("\(DateFormatter.yiRiDay.string(from: date)) · 工时独立记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(YiRiTheme.panel.opacity(0.72))
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(YiRiTheme.border.opacity(0.6), lineWidth: 1)
                    }
                    .opacity(appeared ? 1 : 0)

                Spacer(minLength: 36)
            }
            .padding(34)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.84)) {
                appeared = true
            }
        }
    }
}
