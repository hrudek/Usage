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
        .containerBackground(for: .widget) {
            WidgetBackdrop()
        }
    }
}

// MARK: - System families

/// Widget fonts are fixed sizes: text styles scale with the device's
/// Dynamic Type and overflow the fixed widget height on real hardware.
struct WidgetHeader: View {
    let snapshot: UsageSnapshot
    /// The rendered timeline entry's own date — not `Date()` — so the
    /// peak badge matches whichever entry WidgetKit is currently
    /// displaying, including a future entry dated at the next peak
    /// transition (see `UsageTimelineProvider.peakTransitionEntry`).
    let date: Date
    let accountName: String
    /// The plan pill; the small family leaves it out for room.
    var planName: String? = nil
    var accountIcon: AccountIcon? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                ProviderIdentityView(
                    name: accountName,
                    iconSize: 15,
                    iconCornerRadius: 3.5,
                    font: .system(size: 12, weight: .semibold),
                    nameColor: Theme.ink,
                    planName: planName,
                    icon: accountIcon,
                    showsMark: false
                )
            }
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
}

struct WidgetMarkBand<Leading: View>: View {
    let icon: AccountIcon?
    let leading: Leading

    init(icon: AccountIcon? = nil, @ViewBuilder leading: () -> Leading) {
        self.icon = icon
        self.leading = leading()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                leading
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            ProviderMark(size: WidgetMetrics.markSize, cornerRadius: WidgetMetrics.markRadius, icon: icon)
        }
        .frame(height: WidgetMetrics.markSize)
    }
}

struct WidgetWindowTitle: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.inkSecondary)
            .lineLimit(1)
    }
}

/// Small: the app's account card in a small square (4.0) — the header,
/// the session as the protagonist (its name, the figure large,
/// a thicker bar, and the reset beside the figure as a bare live
/// countdown), then up to two other windows as compact lines (name, a thin
/// bar, the figure). The same `AccountCardLayout` decides which leads, so
/// the widget and the Dashboard always agree. The medium family is
/// `MediumUsageView`, in columns.
struct SystemUsageView: View {
    let snapshot: UsageSnapshot
    let prefs: Preferences
    let date: Date
    let accountName: String
    var accountIcon: AccountIcon? = nil

    var body: some View {
        let layout = AccountCardLayout(snapshot: snapshot, modelSlotFallback: prefs.modelSlotFallback)
        VStack(alignment: .leading, spacing: 0) {
            WidgetMarkBand(icon: accountIcon) {
                WidgetHeader(snapshot: snapshot, date: date, accountName: accountName)
                Spacer(minLength: 0)
                WidgetWindowTitle(name: layout.hero.window?.shortTitle ?? layout.hero.kind.shortName)
            }
            WidgetHero(
                window: layout.hero.window,
                prefs: prefs,
                now: date,
                moneySubtitle: prefs.creditsAmountSubtitle(for: layout.hero.kind, snapshot: snapshot),
                figureSize: 28
            )
            .padding(.top, 4)
            Spacer(minLength: 5)
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
    /// 28 pt in the small family, larger where a family has the height
    /// (the all-accounts widget).
    var figureSize: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if let window {
                    Text(verbatim: "\(Int(window.displayedPct(prefs.displayMode)))")
                        .font(Theme.figure(size: figureSize))
                        .foregroundStyle(Theme.ink)
                    Text(verbatim: "%")
                        .font(Theme.figure(size: figureSize * 0.46))
                        .foregroundStyle(Theme.inkSecondary)
                } else {
                    Text(verbatim: "--")
                        .font(Theme.figure(size: figureSize))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 4)
                Group {
                    if let resetsAt = window?.resetsAt {
                        ResetLineText(resetsAt: resetsAt, style: prefs.resetStyle, now: now, bare: true)
                    } else if let moneySubtitle {
                        Text(moneySubtitle)
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            UsageBarView(
                value: window?.displayedPct(prefs.displayMode),
                tint: window?.tint(usageColors: prefs.usageColors) ?? Theme.accent,
                height: 7,
                lit: true
            )
        }
        .accessibilityElement(children: .combine)
    }
}

/// A widget card's other windows, one line each: name, a thin bar, the
/// figure, in shared columns so the bars start and end together (the
/// app card's `CompactWindowRows`, at widget sizes).
struct WidgetCompactRows: View {
    let slots: [AccountCardLayout.Slot]
    let prefs: Preferences

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(slots, id: \.kind) { slot in
                let window = slot.window
                GridRow {
                    Text(window?.shortTitle ?? slot.kind.shortName)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .layoutPriority(1)
                    UsageBarView(
                        value: window?.displayedPct(prefs.displayMode),
                        tint: window?.tint(usageColors: prefs.usageColors) ?? Theme.accent,
                        height: 4
                    )
                    .frame(minWidth: 24)
                    .accessibilityHidden(true)
                    Text(verbatim: window.map { "\(Int($0.displayedPct(prefs.displayMode)))%" } ?? "--")
                        .font(Theme.figure(size: 11))
                        .foregroundStyle(window == nil ? Theme.inkSecondary : Theme.ink)
                        .gridColumnAlignment(.trailing)
                }
                // One VoiceOver stop a row, name and figure together.
                .accessibilityElement(children: .combine)
            }
        }
    }
}
