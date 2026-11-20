import SwiftUI
import WidgetKit
import UsageKit

/// Single-limit widget body (4.0): the app card's protagonist alone in
/// the square — the account, the picked window's name, its figure large
/// with "%" (and "left" in remaining mode), a thick bar and its reset — so it reads like
/// the Dashboard's card and the small Usage Limits widget. Or, with the
/// ring style picked in Edit Widget, the figure in a ring
/// (`RingUsageView`).
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
            SingleUsageHeader(entry: entry) {
                WidgetWindowTitle(name: entry.windowName)
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if let window = entry.window {
                    Text(verbatim: "\(Int(window.displayedPct(prefs.displayMode)))")
                        .font(Theme.figure(size: 40))
                        .foregroundStyle(Theme.ink)
                    Text(verbatim: "%")
                        .font(Theme.figure(size: 17))
                        .foregroundStyle(Theme.inkSecondary)
                    if let suffix = prefs.displayMode.widgetSuffix {
                        Text(suffix)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.inkSecondary)
                            .padding(.leading, 3)
                    }
                } else {
                    Text(verbatim: "--")
                        .font(Theme.figure(size: 40))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
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
            .padding(.top, 7)
        } else if let amount = entry.prefs.creditsAmountSubtitle(for: entry.kind, snapshot: entry.snapshot) {
            HStack(spacing: 3) {
                Image(systemName: "dollarsign.circle")
                Text(amount)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.inkSecondary)
            .lineLimit(1)
            .padding(.top, 7)
        }
    }
}

extension SingleUsageEntry {
    /// The picked window's compact name with its real length, else the
    /// kind's own while the account has no window of it.
    var windowName: String { window?.shortTitle ?? kind.shortName }
}

/// The account's name over the window's name, with the mark beside them.
private struct SingleUsageHeader<WindowTitle: View>: View {
    let entry: SingleUsageEntry
    @ViewBuilder let windowTitle: WindowTitle

    var body: some View {
        WidgetMarkBand(icon: entry.accountIcon) {
            HStack(spacing: 5) {
                ProviderIdentityView(
                    name: entry.accountName,
                    iconSize: 15,
                    iconCornerRadius: 3.5,
                    font: .system(size: 12, weight: .semibold),
                    nameColor: Theme.ink,
                    planName: nil,
                    icon: entry.accountIcon,
                    showsMark: false
                )
            }
            Spacer(minLength: 0)
            windowTitle
        }
    }
}

/// The ring style: the header, the window's name, then the window as a ring
/// in its level's color with only its figure and its reset in the centre
/// (the bare live countdown under a day, `ResetLineText(bare:)`), clear
/// of the stroke, and 4 pt of air under the header band (Mike's review,
/// 2026-10-21: no "used", and room around the ring). The band's mark
/// leaves the ring less height than a slim header did, so the figure is
/// 24 pt. The track is the bars' and the stroke 9 pt.
private struct RingUsageView: View {
    let entry: SingleUsageEntry
    private static let strokeWidth: CGFloat = 9

    var body: some View {
        let prefs = entry.prefs
        VStack(alignment: .leading, spacing: 0) {
            SingleUsageHeader(entry: entry) {
                Text(entry.windowName)
                    .font(.system(size: 11))
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
                VStack(spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(verbatim: entry.window.map { "\(Int($0.displayedPct(prefs.displayMode)))" } ?? "--")
                            .font(Theme.figure(size: 24))
                            .foregroundStyle(entry.window == nil ? Theme.inkSecondary : Theme.ink)
                        if entry.window != nil {
                            Text(verbatim: "%")
                                .font(Theme.figure(size: 11))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    caption
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.inkSecondary)
                }
                // Clear of the stroke: the figure and the reset never come
                // closer to the ring than its own width.
                .padding(.horizontal, 20)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            // The stroke straddles the circle's edge: half of it lies
            // outside the frame without this.
            .padding(Self.strokeWidth / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // One VoiceOver element: "42, %, 2:23:05".
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
