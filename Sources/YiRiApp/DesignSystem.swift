import SwiftUI

enum YiRiTheme {
    static let accent = dynamic(
        light: NSColor(red: 0.43, green: 0.58, blue: 0.46, alpha: 1),
        dark: NSColor(red: 0.68, green: 0.80, blue: 0.69, alpha: 1)
    )
    static let accentSoft = dynamic(
        light: NSColor(red: 0.94, green: 0.97, blue: 0.93, alpha: 1),
        dark: NSColor(red: 0.19, green: 0.24, blue: 0.20, alpha: 1)
    )
    static let warm = dynamic(
        light: NSColor(red: 0.97, green: 0.94, blue: 0.88, alpha: 1),
        dark: NSColor(red: 0.29, green: 0.25, blue: 0.20, alpha: 1)
    )
    static let page = dynamic(
        light: NSColor(red: 0.98, green: 0.98, blue: 0.97, alpha: 1),
        dark: NSColor(red: 0.09, green: 0.10, blue: 0.09, alpha: 1)
    )
    static let panel = dynamic(
        light: NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),
        dark: NSColor(red: 0.14, green: 0.15, blue: 0.14, alpha: 1)
    )
    static let secondaryPanel = dynamic(
        light: NSColor(red: 0.96, green: 0.97, blue: 0.95, alpha: 1),
        dark: NSColor(red: 0.17, green: 0.19, blue: 0.17, alpha: 1)
    )
    static let inputBackground = dynamic(
        light: NSColor(red: 0.985, green: 0.99, blue: 0.98, alpha: 1),
        dark: NSColor(red: 0.15, green: 0.17, blue: 0.15, alpha: 1)
    )
    static let border = dynamic(
        light: NSColor(red: 0.88, green: 0.90, blue: 0.87, alpha: 1),
        dark: NSColor(red: 0.25, green: 0.29, blue: 0.25, alpha: 1)
    )
    static let completionColumn = dynamic(
        light: NSColor(red: 0.965, green: 0.978, blue: 0.958, alpha: 1),
        dark: NSColor(red: 0.145, green: 0.178, blue: 0.150, alpha: 1)
    )
    static let completionSoft = dynamic(
        light: NSColor(red: 0.925, green: 0.962, blue: 0.915, alpha: 1),
        dark: NSColor(red: 0.185, green: 0.245, blue: 0.190, alpha: 1)
    )
    static let completionBorder = dynamic(
        light: NSColor(red: 0.760, green: 0.855, blue: 0.742, alpha: 1),
        dark: NSColor(red: 0.315, green: 0.455, blue: 0.325, alpha: 1)
    )
    static let completionHighlight = dynamic(
        light: NSColor(red: 0.820, green: 0.900, blue: 0.705, alpha: 1),
        dark: NSColor(red: 0.415, green: 0.585, blue: 0.390, alpha: 1)
    )

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

    static let yiRiSidebarDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}
