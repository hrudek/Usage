import SwiftUI
import WidgetKit
import UsageKit

struct MediumUsageView: View {
    let snapshot: UsageSnapshot
    let prefs: Preferences
    let date: Date
    let accountName: String
    var accountIcon: AccountIcon? = nil

    var body: some View {
        let slots = WindowSlots(snapshot: snapshot, modelSlotFallback: prefs.modelSlotFallback).slots
        let wide = slots.count <= 2
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(snapshot: snapshot, date: date, accountName: accountName, planName: snapshot.planName, accountIcon: accountIcon)
                Spacer(minLength: 6)
                HStack(alignment: .top, spacing: wide ? 16 : 10) {
                    ForEach(slots, id: \.kind) { slot in
                        WindowColumn(
                            kind: slot.kind,
                            window: slot.window,
                            prefs: prefs,
                            now: date,
                            valueSize: wide ? 28 : 22,
                            moneySubtitle: prefs.creditsAmountSubtitle(for: slot.kind, snapshot: snapshot)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Spacer(minLength: 0)
            }
            ProviderMark(size: WidgetMetrics.markSize, cornerRadius: WidgetMetrics.markRadius, icon: accountIcon)
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
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if let window {
                    Text("\(Int(window.displayedPct(prefs.displayMode)))%")
                        .font(Theme.figure(size: valueSize))
                        .foregroundStyle(Theme.ink)
                    if let suffix = prefs.displayMode.widgetSuffix {
                        Text(suffix)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                } else {
                    Text("--")
                        .font(Theme.figure(size: valueSize))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            // Fixed height, so the bars line up across columns whatever
            // the glyphs above them (a dash measures shorter than digits).
            .frame(height: ceil(valueSize * 1.2), alignment: .leading)
            .padding(.top, 2)
            UsageBarView(
                value: window?.displayedPct(prefs.displayMode),
                tint: window?.tint(usageColors: prefs.usageColors) ?? Theme.accent
            )
            .padding(.top, 7)
            subtitle
                .font(.system(size: 9))
                .foregroundStyle(Theme.inkSecondary.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
