import SwiftUI
import WidgetKit
import UsageKit
import AppIntents

/// System families show the account header plus capsule bars with reset
/// times: the small family as stacked rows mirroring the dashboard, the
/// medium as side-by-side columns with a big figure each. All views honor
/// the Remaining/Used and Relative/Absolute preferences from the App Group.
struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    /// False in StandBy (and on an iPad's Lock Screen): the small family
    /// draws `StandByUsageView` there.
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    let entry: UsageEntry

    var body: some View {
        Group {
            if let snapshot = entry.shownSnapshot {
                switch family {
                case .accessoryCircular:
                    CircularUsageView(snapshot: snapshot, prefs: entry.prefs)
                        .widgetMargins()
                case .accessoryRectangular:
                    RectangularUsageView(snapshot: snapshot, prefs: entry.prefs)
                        .widgetMargins()
                case .accessoryInline:
                    InlineUsageView(snapshot: snapshot, prefs: entry.prefs)
                        .widgetMargins()
                case .systemMedium:
                    MediumUsageView(snapshot: snapshot, prefs: entry.prefs, date: entry.date, accountName: entry.accountName, accountIcon: entry.accountIcon)
                        .refreshesOnTap(RefreshAccountIntent(accountID: entry.accountID))
                case .systemSmall where !showsBackground:
                    let hero = AccountCardLayout(snapshot: snapshot, modelSlotFallback: entry.prefs.modelSlotFallback).hero
                    StandByUsageView(
                        accountName: entry.accountName,
                        windowName: hero.window?.shortTitle ?? hero.kind.shortName,
                        window: hero.window,
                        prefs: entry.prefs,
                        now: entry.date,
                        moneySubtitle: entry.prefs.creditsAmountSubtitle(for: hero.kind, snapshot: snapshot)
                    )
                    .widgetMargins()
                default:
                    SystemUsageView(snapshot: snapshot, prefs: entry.prefs, date: entry.date, accountName: entry.accountName, accountIcon: entry.accountIcon)
                        .refreshesOnTap(RefreshAccountIntent(accountID: entry.accountID))
                }
            } else {
                Text("Open Usage to load your limits")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .refreshesOnTap(RefreshAccountIntent(accountID: entry.accountID))
            }
        }
        .widgetBackdrop()
    }
}

// MARK: - System families

struct SystemUsageView: View {
    let snapshot: UsageSnapshot
    let prefs: Preferences
    let date: Date
    let accountName: String
    var accountIcon: AccountIcon? = nil

    var body: some View {
        let layout = AccountCardLayout(snapshot: snapshot, modelSlotFallback: prefs.modelSlotFallback)
        VStack(alignment: .leading, spacing: 0) {
            WidgetCardHeader(title: Text(accountName), planName: snapshot.planName, icon: accountIcon, snapshot: snapshot)
            WidgetWindowTitle(name: layout.hero.window?.shortTitle ?? layout.hero.kind.shortName)
                .padding(.top, WidgetMetrics.dividerGap)
            WidgetHero(
                window: layout.hero.window,
                prefs: prefs,
                now: date,
                moneySubtitle: prefs.creditsAmountSubtitle(for: layout.hero.kind, snapshot: snapshot),
                figureSize: 26
            )
            Spacer(minLength: 4)
            WidgetCompactRows(slots: Array(layout.others.prefix(2)), prefs: prefs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct WidgetHero: View {
    let window: UsageWindow?
    let prefs: Preferences
    let now: Date
    let moneySubtitle: String?
    var figureSize: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                WidgetFigure(window: window, mode: prefs.displayMode, size: figureSize)
                Group {
                    if let resetsAt = window?.resetsAt {
                        ResetLineText(resetsAt: resetsAt, style: prefs.resetStyle, now: now, bare: true)
                    } else if let moneySubtitle {
                        Text(moneySubtitle)
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            UsageBarView(
                value: window?.displayedPct(prefs.displayMode),
                tint: window?.tint(usageColors: prefs.usageColors) ?? Theme.accent,
                height: 8,
                lit: true
            )
        }
        .accessibilityElement(children: .combine)
    }
}

struct WidgetCompactRows: View {
    let slots: [AccountCardLayout.Slot]
    let prefs: Preferences

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
            ForEach(slots, id: \.kind) { slot in
                let window = slot.window
                GridRow {
                    Text(window?.shortTitle ?? slot.kind.shortName)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .layoutPriority(1)
                    UsageBarView(
                        value: window?.displayedPct(prefs.displayMode),
                        tint: window?.tint(usageColors: prefs.usageColors) ?? Theme.accent,
                        height: 6
                    )
                    .frame(minWidth: 16)
                    Text(verbatim: WidgetFigure.text(window, prefs.displayMode))
                        .font(Theme.figure(size: 11))
                        .foregroundStyle(window == nil ? Theme.inkSecondary : Theme.ink)
                        .lineLimit(1)
                        .fixedSize()
                        .layoutPriority(2)
                        .gridColumnAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
