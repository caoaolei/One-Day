import SwiftUI

enum YiRiTheme {
    static let accent = dynamic(
        light: NSColor(red: 0.26, green: 0.39, blue: 0.28, alpha: 1),
        dark: NSColor(red: 0.66, green: 0.79, blue: 0.64, alpha: 1)
    )
    static let accentSoft = dynamic(
        light: NSColor(red: 0.90, green: 0.94, blue: 0.89, alpha: 1),
        dark: NSColor(red: 0.20, green: 0.26, blue: 0.20, alpha: 1)
    )
    static let warm = dynamic(
        light: NSColor(red: 0.95, green: 0.90, blue: 0.82, alpha: 1),
        dark: NSColor(red: 0.29, green: 0.24, blue: 0.19, alpha: 1)
    )
    static let page = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let secondaryPanel = Color(nsColor: .underPageBackgroundColor)
    static let border = Color(nsColor: .separatorColor)

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

struct Panel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(YiRiTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(YiRiTheme.border.opacity(0.7), lineWidth: 1)
            }
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct StatView: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyState: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }
}

extension View {
    func yiRiPage() -> some View {
        self
            .padding(26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(YiRiTheme.page)
    }
}

extension DateFormatter {
    static let yiRiDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日 · EEEE"
        return formatter
    }()

    static let yiRiTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
