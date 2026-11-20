import SwiftUI
import UsageKit

/// Presentation helpers shared by app and widgets. Rendering is driven by
/// whatever windows the snapshot contains — no provider names hardcoded.
extension UsageWindow.Kind {
    /// Row title on dashboard/detail for a kind on its own: "5-hour
    /// session", "Weekly", "Weekly · Fable". With the
    /// window at hand, `UsageWindow.title` reads its real length instead
    /// (a 30-day week is "Monthly").
    var displayName: String {
        title(duration: nil)
    }

    /// Compact label for widgets; `UsageWindow.shortTitle`
    /// with the window's length.
    var shortName: String {
        shortTitle(duration: nil)
    }

    /// The row title for a window of this kind and length: the length
    /// is the provider's, so a session is "5-hour" or "3-hour", and the
    /// overall period "Weekly", "Monthly" or "14-day"; a per-model window
    /// follows the same period.
    func title(duration: TimeInterval?) -> String {
        switch self {
        case .session:
            let hours = Self.hours(duration)
            return hours == 5 ? String(localized: "5-hour session") : String(localized: "\(hours)-hour session")
        case .weekly:
            switch Self.period(duration) {
            case .week: return String(localized: "Weekly")
            case .month: return String(localized: "Monthly")
            case .days(let days): return String(localized: "\(days)-day window")
            }
        case .modelSpecific(let model):
            switch Self.period(duration) {
            case .week: return String(localized: "Weekly · \(model)")
            case .month: return String(localized: "Monthly · \(model)")
            case .days(let days): return String(localized: "\(days)-day · \(model)")
            }
        case .credits:
            return String(localized: "Credits")
        }
    }

    /// The compact name for a window of this kind and length.
    func shortTitle(duration: TimeInterval?) -> String {
        switch self {
        case .session:
            return String(localized: "Session")
        case .weekly:
            switch Self.period(duration) {
            case .week: return String(localized: "Week")
            case .month: return String(localized: "Month")
            case .days(let days): return String(localized: "\(days)d")
            }
        case .modelSpecific(let model):
            return model
        case .credits:
            return String(localized: "Credits")
        }
    }

    var symbolName: String {
        switch self {
        case .session: return "clock"
        case .weekly: return "calendar"
        case .modelSpecific: return "sparkles"
        case .credits: return "creditcard"
        }
    }

    /// How a periodic window's length reads: a week (the default with no
    /// length stated), a calendar month, or a count of days.
    enum Period: Equatable {
        case week
        case month
        case days(Int)
    }

    static func period(_ duration: TimeInterval?) -> Period {
        guard let duration, duration > 0 else { return .week }
        let days = Int((duration / 86_400).rounded())
        switch days {
        case 6...8: return .week
        case 27...32: return .month
        default: return .days(max(days, 1))
        }
    }

    /// A session's length in whole hours; Claude's five with no length
    /// stated.
    static func hours(_ duration: TimeInterval?) -> Int {
        guard let duration, duration > 0 else { return 5 }
        return max(1, Int((duration / 3600).rounded()))
    }
}

extension UsageWindow {
    /// The row title, from the kind and the provider's own length.
    var title: String { kind.title(duration: effectiveDuration) }

    /// The compact name, from the kind and the provider's own length.
    var shortTitle: String { kind.shortTitle(duration: effectiveDuration) }
}

/// How close a window is to its limit — the one decision behind every
/// bar and percentage color. Accent up to 70 % used, yellow from 71 % (or
/// when the provider flags a warning), red from 86 % (or when the
/// provider flags trouble). Three colors, nothing else — and only while
/// the user keeps usage colors on (`Preferences.usageColors`); off, every
/// bar draws at `.normal`.
enum UsageLevel: Int, Comparable {
    case normal, warning, danger

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Usage *above* these turns the level: 70 % is still the accent, 85 % still
    /// yellow.
    static let warningAbove: Double = 70
    static let dangerAbove: Double = 85

    init(usedPct: Double, severity: UsageWindow.Severity?) {
        // Compared on the whole percent every surface prints (they all
        // truncate), so a bar that reads "70%" is never yellow and one that
        // reads "85%" is never red; the endpoint does report fractions.
        let shown = usedPct.rounded(.down)
        if severity == .critical || severity == .exceeded || shown > Self.dangerAbove {
            self = .danger
        } else if severity == .warning || shown > Self.warningAbove {
            self = .warning
        } else {
            self = .normal
        }
    }

    var color: Color {
        switch self {
        case .normal: Theme.accent
        case .warning: Theme.warning
        case .danger: Theme.danger
        }
    }
}

extension UsageWindow {
    var level: UsageLevel { UsageLevel(usedPct: usedPct, severity: severity) }

    /// The level the bar is drawn at: `level`, or `.normal` at every figure
    /// while usage colors are off (`Preferences.usageColors`).
    func level(usageColors: Bool) -> UsageLevel { usageColors ? level : .normal }

    /// The bar's color — `level(usageColors:)`'s.
    func tint(usageColors: Bool) -> Color { level(usageColors: usageColors).color }

    /// Same decision as `tint(usageColors:)`, callable without a full
    /// `UsageWindow`, for a caller that only has `usedPct`/`severity`.
    static func tint(usedPct: Double, severity: Severity?, usageColors: Bool) -> Color {
        (usageColors ? UsageLevel(usedPct: usedPct, severity: severity) : .normal).color
    }
}

extension UsageSnapshot {
    var isStale: Bool {
        Date().timeIntervalSince(fetchedAt) > AppConfig.staleAfter
    }

    /// The row title of this account's window of `kind`, with its real
    /// length when the snapshot has it, else the kind's own.
    func title(for kind: UsageWindow.Kind) -> String {
        window(for: kind)?.title ?? kind.displayName
    }
}

extension UsagePace.Status {
    /// Short caption shown next to the reset line. Localized in the app's
    /// catalog (UsageKit core carries no UI strings beyond errors).
    var label: String {
        switch self {
        case .onPace: return String(localized: "On pace")
        case .ahead: return String(localized: "Ahead of pace")
        case .behind: return String(localized: "Behind pace")
        }
    }
}
