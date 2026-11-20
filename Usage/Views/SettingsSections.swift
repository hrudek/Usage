import SwiftUI
import UsageKit


// The sections of Settings, one view each (header, card, footnote),
// stacked in one list by `SettingsView`. A section
// never adds the gap around itself; the list that places it does.

/// The space between two sections of a Settings list.
struct SettingsGap: View {
    var body: some View {
        Spacer().frame(height: Theme.sectionSpacing - 16)
    }
}


/// "Appearance", "Display", "Usage colors" and "Reset timers": how every
/// surface draws the figures.
struct AppearanceSettings: View {
    @Environment(PreferencesModel.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "Appearance"))
        Card {
            SegmentedPill(
                options: AppearanceMode.allCases.map { ($0, $0.label) },
                selection: $prefs.appearance,
                name: String(localized: "Appearance")
            )
        }

        SettingsGap()
        SectionHeader(title: String(localized: "Display"))
        Card {
            SegmentedPill(
                options: [DisplayMode.remaining, .used].map { ($0, $0.label) },
                selection: $prefs.displayMode,
                name: String(localized: "Display")
            )
        }
        SectionFootnote(text: String(localized: "Whether bars and percentages show how much you have left or how much you've used."))

        SettingsGap()
        SectionHeader(title: String(localized: "Usage colors"))
        Card {
            Toggle(isOn: $prefs.usageColors) {
                Text("Yellow and red")
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.accent)
        }
        SectionFootnote(text: String(localized: "Bars turn yellow above 70% used and red above 85%. Off, every bar stays one color."))

        SettingsGap()
        SectionHeader(title: String(localized: "Reset timers"))
        Card {
            SegmentedPill(
                options: [ResetStyle.relative, .absolute].map { ($0, $0.label) },
                selection: $prefs.resetStyle,
                name: String(localized: "Reset timers")
            )
        }
        SectionFootnote(text: String(localized: "Relative counts down to the reset. Absolute shows the local time. Tap any reset label on the dashboard to switch."))
    }
}



/// The refresh cadence, rescheduling the platform's background work as it
/// changes.
struct BackgroundRefreshSettings: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "Background refresh"))
        Card {
            HStack {
                Text("Refresh usage")
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Picker("Refresh usage", selection: $prefs.refreshCadence) {
                    ForEach(RefreshCadence.allCases, id: \.self) { cadence in
                        Text(cadence.label).tag(cadence)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .tint(Theme.accent)
            }
        }
        .onChange(of: prefs.refreshCadence) { _, newValue in
            BackgroundRefresh.scheduleNext()
        }
        SectionFootnote(text: footnote)
    }

    private var footnote: String {
        var text: String
        text = String(localized: "Usage refreshes your limits in the background when iOS permits it, then updates your widgets. Timing depends on battery, connectivity, and how often you use the app.")
        if let scheduled = prefs.lastScheduledAt {
            let minutes = max(0, Int(Date().timeIntervalSince(scheduled) / 60))
            text += "\n" + String(localized: "Scheduled \(minutes) minutes ago.")
        }
        return text
    }
}

/// The row that pushes Privacy & data.
struct PrivacyLinkSettings: View {
    var body: some View {
        Card {
            NavigationLink {
                PrivacyView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28, height: 28)
                        .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text("Privacy & data")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        SectionFootnote(text: String(localized: "How connecting works, what the app can access, and where your data lives."))
    }
}

