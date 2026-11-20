import SwiftUI
import WidgetKit
import UsageKit
import AppIntents

/// The standard layout; `CondensedAccountsView` is the other.
struct AllAccountsWidgetView: View {
    let entry: AllAccountsEntry
    /// Each account renders its full window rows (reset lines included),
    /// same detail level as `UsageLimits` — not the density-optimized
    /// compact style, so it takes real vertical room. Two accounts is what
    /// comfortably fits a `.systemLarge` frame without scrolling; static,
    /// non-scrolling content is the safer choice for widgets, so this caps
    /// rather than fights WidgetKit's own gesture handling.
    private static let maxRows = 2

    var body: some View {
        Group {
            if entry.layout == .condensed {
                CondensedAccountsView(entry: entry)
            } else {
                standard
            }
        }
        .refreshesOnTap(RefreshAllAccountsIntent())
        .containerBackground(for: .widget) {
            WidgetBackdrop()
        }
    }

    private var standard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if entry.rows.isEmpty {
                Text("Open Usage to load your limits")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let visible = Array(entry.rows.prefix(Self.maxRows))
                // The accounts share the height: the first at the top, the
                // last at the bottom, the room left over between them.
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Spacer(minLength: 14)
                    }
                    AccountRow(row: row, prefs: entry.prefs, now: entry.date)
                }
                if entry.rows.count > Self.maxRows {
                    Text("+\(entry.rows.count - Self.maxRows) more")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkSecondary)
                }
                if visible.count < 2 {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One account's header (the name over its protagonist's name, the mark
/// beside them) followed by the app's card composition (4.0): its session
/// as the protagonist and the others as compact lines, `WidgetHero` and
/// `WidgetCompactRows`, the small widget's own pieces, decided by the same
/// `AccountCardLayout`.
private struct AccountRow: View {
    let row: AllAccountsEntry.Row
    let prefs: Preferences
    let now: Date

    var body: some View {
        let layout = row.snapshot.map { AccountCardLayout(snapshot: $0, modelSlotFallback: prefs.modelSlotFallback) }
        VStack(alignment: .leading, spacing: 4) {
            WidgetMarkBand(icon: row.account.icon) {
                HStack(spacing: 5) {
                    ProviderIdentityView(
                        name: row.account.displayName,
                        iconSize: 15,
                        iconCornerRadius: 3.5,
                        font: .system(size: 12, weight: .semibold),
                        nameColor: Theme.ink,
                        planName: row.snapshot?.planName,
                        icon: row.account.icon,
                        showsMark: false
                    )
                }
                Spacer(minLength: 0)
                if let hero = layout?.hero {
                    WidgetWindowTitle(name: hero.window?.shortTitle ?? hero.kind.shortName)
                } else {
                    Text("No usage data yet")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            if let snapshot = row.snapshot, let layout {
                WidgetHero(
                    window: layout.hero.window,
                    prefs: prefs,
                    now: now,
                    moneySubtitle: prefs.creditsAmountSubtitle(for: layout.hero.kind, snapshot: snapshot),
                    figureSize: 34
                )
                .padding(.bottom, 10)
                WidgetCompactRows(slots: layout.others, prefs: prefs)
            }
        }
    }
}
