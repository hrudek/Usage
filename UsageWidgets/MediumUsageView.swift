import SwiftUI
import WidgetKit
import UsageKit

struct MediumUsageView: View {
    let snapshot: UsageSnapshot
    let prefs: Preferences
    let date: Date
    let accountName: String
    var accountIcon: AccountIcon? = nil

    private static let columnGap: CGFloat = 20

    var body: some View {
        let slots = WindowSlots(snapshot: snapshot, modelSlotFallback: prefs.modelSlotFallback).slots
        let wide = slots.count <= 2
        VStack(alignment: .leading, spacing: 0) {
            WidgetCardHeader(title: Text(accountName), planName: snapshot.planName, icon: accountIcon, snapshot: snapshot)
            Spacer(minLength: WidgetMetrics.dividerGap)
            HStack(alignment: .top, spacing: Self.columnGap) {
                ForEach(Array(slots.enumerated()), id: \.element.kind) { index, slot in
                    WindowColumn(
                        kind: slot.kind,
                        window: slot.window,
                        prefs: prefs,
                        now: date,
                        valueSize: wide ? 28 : 24,
                        moneySubtitle: prefs.creditsAmountSubtitle(for: slot.kind, snapshot: snapshot)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        if index > 0 {
                            Rectangle()
                                .fill(Theme.track)
                                .frame(width: 1)
                                .offset(x: -Self.columnGap / 2)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct WindowColumn: View {
    let kind: UsageWindow.Kind
    let window: UsageWindow?
    let prefs: Preferences
    let now: Date
    let valueSize: CGFloat
    let moneySubtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(window?.shortTitle ?? kind.shortName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
            WidgetFigure(window: window, mode: prefs.displayMode, size: valueSize)
                // Fixed height, so the bars line up across columns whatever
                // the glyphs above them (a dash measures shorter than digits).
                .frame(height: ceil(valueSize * 1.2), alignment: .leading)
            UsageBarView(
                value: window?.displayedPct(prefs.displayMode),
                tint: window?.tint(usageColors: prefs.usageColors) ?? Theme.accent,
                height: 8,
                lit: true
            )
            .padding(.top, 6)
            subtitle
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 5)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var subtitle: some View {
        if let resetsAt = window?.resetsAt {
            ResetLineText(resetsAt: resetsAt, style: prefs.resetStyle, now: now)
        } else if let moneySubtitle {
            HStack(spacing: 3) {
                Image(systemName: "dollarsign.circle")
                Text(moneySubtitle)
            }
        } else if window == nil {
            Text("Not available")
        } else {
            // A window with no reset date (an idle session): keep the
            // column's height so the bars across columns stay aligned.
            Text(" ")
        }
    }
}
