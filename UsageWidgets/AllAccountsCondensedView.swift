import SwiftUI
import WidgetKit
import UsageKit

struct CondensedAccountsView: View {
    let entry: AllAccountsEntry
    static let maxRows = 6
    private static let nameWidth: CGFloat = 58
    private static let figureWidth: CGFloat = 40

    var body: some View {
        let rows = Array(entry.rows.prefix(Self.maxRows))
        VStack(alignment: .leading, spacing: 0) {
            header
            if entry.rows.isEmpty {
                Text("Open Usage to load your limits")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 10)
                // The lines share the height, the room left over between
                // them.
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Spacer(minLength: 8)
                    }
                    line(row)
                }
                if entry.rows.count > Self.maxRows {
                    Text("+\(entry.rows.count - Self.maxRows) more")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.top, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        WidgetCardHeader(title: Text("All Accounts")) {
            nextReset
        }
    }

    private func line(_ row: AllAccountsEntry.Row) -> some View {
        let prefs = entry.prefs
        let layout = AccountCardLayout(snapshot: row.shownSnapshot, modelSlotFallback: prefs.modelSlotFallback)
        let hero = layout.hero.window
        let figures = ([layout.hero] + layout.others)
            .map { "\($0.window?.shortTitle ?? $0.kind.shortName) \(WidgetFigure.text($0.window, prefs.displayMode))" }
            .joined(separator: "  ·  ")
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(row.account.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: Self.nameWidth, alignment: .leading)
                UsageBarView(
                    value: hero?.displayedPct(prefs.displayMode),
                    tint: hero?.tint(usageColors: prefs.usageColors) ?? Theme.accent,
                    height: 8,
                    lit: true
                )
                WidgetFigure(window: hero, mode: prefs.displayMode, size: 15)
                    .fixedSize()
                    .frame(minWidth: Self.figureWidth, alignment: .trailing)
            }
            if row.snapshot != nil {
                Text(verbatim: figures)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.leading, Self.nameWidth + 10)
            }
        }
        // One VoiceOver element per account: its name and every window's
        // figure; the bar is decorative.
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var nextReset: some View {
        let soonest = entry.rows
            .compactMap { row in row.snapshot?.windows.first { $0.kind == .session }?.resetsAt }
            .filter { $0 > entry.date }
            .min()
        if let soonest {
            HStack(spacing: 3) {
                Text("Next session reset:")
                ResetLineText(resetsAt: soonest, style: entry.prefs.resetStyle, now: entry.date, bare: true)
            }
            .font(.system(size: 9))
            .foregroundStyle(Theme.inkSecondary.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }
}
