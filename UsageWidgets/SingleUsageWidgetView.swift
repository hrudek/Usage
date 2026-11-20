import SwiftUI
import WidgetKit
import UsageKit

struct SingleUsageWidgetView: View {
    let entry: SingleUsageEntry
    /// False in StandBy (and on an iPad's Lock Screen): either style draws
    /// `StandByUsageView` there.
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    var body: some View {
        Group {
            if !showsBackground {
                StandByUsageView(
                    accountName: entry.accountName,
                    windowName: entry.windowName,
                    window: entry.window,
                    prefs: entry.prefs,
                    now: entry.date,
                    moneySubtitle: entry.snapshot.flatMap { entry.prefs.creditsAmountSubtitle(for: entry.kind, snapshot: $0) }
                )
                .widgetMargins()
            } else if entry.style == .ring {
                RingUsageView(entry: entry)
                    .refreshesOnTap(RefreshAccountIntent(accountID: entry.accountID))
            } else {
                bars
                    .refreshesOnTap(RefreshAccountIntent(accountID: entry.accountID))
            }
        }
        .containerBackground(for: .widget) {
            WidgetBackdrop()
        }
    }

    private var bars: some View {
        let prefs = entry.prefs
        return VStack(alignment: .leading, spacing: 0) {
            WidgetCardHeader(title: Text(entry.accountName), planName: entry.snapshot?.planName, icon: entry.accountIcon)
            WidgetWindowTitle(name: entry.windowName)
                .padding(.top, WidgetMetrics.dividerGap)
            WidgetFigure(window: entry.window, mode: prefs.displayMode, size: 34)
            Spacer(minLength: 3)
            UsageBarView(
                value: entry.window?.displayedPct(prefs.displayMode),
                tint: entry.window?.tint(usageColors: prefs.usageColors) ?? Theme.accent,
                height: 8,
                lit: true
            )
            resetLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var resetLine: some View {
        if let resetsAt = entry.window?.resetsAt {
            ResetLineText(resetsAt: resetsAt, style: entry.prefs.resetStyle, now: entry.date)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 7)
        } else if let amount = entry.prefs.creditsAmountSubtitle(for: entry.kind, snapshot: entry.snapshot) {
            HStack(spacing: 3) {
                Image(systemName: "dollarsign.circle")
                Text(amount)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.inkSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.top, 7)
        }
    }
}

extension SingleUsageEntry {
    /// The picked window's compact name with its real length, else the
    /// kind's own while the account has no window of it.
    var windowName: String { window?.shortTitle ?? kind.shortName }
}

private struct RingUsageView: View {
    let entry: SingleUsageEntry
    private static let strokeWidth: CGFloat = 9

    var body: some View {
        let prefs = entry.prefs
        VStack(alignment: .leading, spacing: 0) {
            WidgetCardHeader(title: Text(entry.accountName), planName: entry.snapshot?.planName, icon: entry.accountIcon) {
                Text(entry.windowName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            ZStack {
                Circle()
                    .stroke(Theme.track, lineWidth: Self.strokeWidth)
                if let window = entry.window {
                    Circle()
                        .trim(from: 0, to: min(max(window.displayedPct(prefs.displayMode), 0), 100) / 100)
                        .stroke(
                            window.tint(usageColors: prefs.usageColors),
                            style: StrokeStyle(lineWidth: Self.strokeWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 2) {
                    WidgetFigure(window: entry.window, mode: prefs.displayMode, size: 22)
                    caption
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, Self.strokeWidth + 6)
            }
            .aspectRatio(1, contentMode: .fit)
            // The stroke straddles the circle's edge: half of it lies
            // outside the frame without this.
            .padding(Self.strokeWidth / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var caption: some View {
        if let resetsAt = entry.window?.resetsAt {
            ResetLineText(resetsAt: resetsAt, style: entry.prefs.resetStyle, now: entry.date, bare: true)
        } else if let amount = entry.prefs.creditsAmountSubtitle(for: entry.kind, snapshot: entry.snapshot) {
            Text(amount)
        }
    }
}
