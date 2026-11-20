import SwiftUI
import UsageKit

/// Widget fonts are fixed sizes: text styles scale with the device's
/// Dynamic Type and overflow the fixed widget height on real hardware.
enum WidgetMetrics {
    static let markSize: CGFloat = 32
    static let markRadius: CGFloat = 9
    static let dividerGap: CGFloat = 6
}

struct WidgetCardHeader<Subtitle: View>: View {
    let title: Text
    var planName: String? = nil
    var icon: AccountIcon? = nil
    let subtitle: Subtitle

    init(title: Text, planName: String? = nil, icon: AccountIcon? = nil, @ViewBuilder subtitle: () -> Subtitle) {
        self.title = title
        self.planName = planName
        self.icon = icon
        self.subtitle = subtitle()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                if let planName {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 5) {
                            styledTitle
                            PlanPill(name: planName, compact: true, font: .system(size: 10, weight: .semibold))
                        }
                        styledTitle
                    }
                } else {
                    styledTitle
                }
                subtitle
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ProviderMark(size: WidgetMetrics.markSize, cornerRadius: WidgetMetrics.markRadius, icon: icon)
        }
        .padding(.bottom, WidgetMetrics.dividerGap + 1)
    }

    private var styledTitle: some View {
        title
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

extension WidgetCardHeader where Subtitle == EmptyView {
    init(title: Text, planName: String? = nil, icon: AccountIcon? = nil) {
        self.init(title: title, planName: planName, icon: icon) { EmptyView() }
    }
}

extension WidgetCardHeader where Subtitle == WidgetStaleHint {
    init(title: Text, planName: String? = nil, icon: AccountIcon? = nil, snapshot: UsageSnapshot) {
        self.init(title: title, planName: planName, icon: icon) { WidgetStaleHint(snapshot: snapshot) }
    }
}

struct WidgetStaleHint: View {
    let snapshot: UsageSnapshot

    var body: some View {
        if snapshot.isStale {
            HStack(spacing: 2) {
                Image(systemName: "clock.arrow.circlepath")
                Text(snapshot.fetchedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
            }
            .font(.system(size: 8))
            .foregroundStyle(Theme.inkSecondary.opacity(0.8))
            .lineLimit(1)
        }
    }
}

struct WidgetWindowTitle: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.inkSecondary)
            .lineLimit(1)
    }
}

struct WidgetFigure: View {
    let window: UsageWindow?
    let mode: DisplayMode
    let size: CGFloat
    var weight: Font.Weight = .bold

    var body: some View {
        Text(verbatim: Self.text(window, mode))
            .font(Theme.figure(size: size, weight: weight))
            .foregroundStyle(window == nil ? Theme.inkSecondary : Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .layoutPriority(1)
    }

    static func text(_ window: UsageWindow?, _ mode: DisplayMode) -> String {
        window.map { "\(Int($0.displayedPct(mode)))%" } ?? "--"
    }
}
