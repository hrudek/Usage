import Foundation
import SwiftUI
import UsageKit

enum DisplayMode: String, CaseIterable {
    case used, remaining

    var label: String {
        switch self {
        case .used: return String(localized: "Used")
        case .remaining: return String(localized: "Remaining")
        }
    }

    /// The word after a big figure: "42% left" / "42% used" (the medium
    /// widget's columns).
    var suffix: String {
        switch self {
        case .used: return String(localized: "used")
        case .remaining: return String(localized: "left")
        }
    }
}

enum ResetStyle: String, CaseIterable {
    case relative, absolute

    var label: String {
        switch self {
        case .relative: return String(localized: "Relative")
        case .absolute: return String(localized: "Absolute")
        }
    }
}

enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }

    /// nil follows the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// What the third usage slot shows when the plan reports no per-model
/// window (e.g. Claude Pro without Fable 5's own weekly limit).
enum ModelSlotFallback: String, CaseIterable {
    /// Shows the credits row exactly when the account's spend/credits
    /// status is enabled, hides it otherwise — no manual choice needed.
    case auto, hidden, credits

    var label: String {
        switch self {
        case .auto: return String(localized: "Auto")
        case .hidden: return String(localized: "Hidden")
        case .credits: return String(localized: "Credits")
        }
    }
}

enum RefreshCadence: Int, CaseIterable {
    case minutes30 = 1800
    case hour1 = 3600
    case hours3 = 10800

    var label: String {
        switch self {
        case .minutes30: return String(localized: "Every 30 minutes")
        case .hour1: return String(localized: "Every hour")
        case .hours3: return String(localized: "Every 3 hours")
        }
    }

    var interval: TimeInterval { TimeInterval(rawValue) }
}

/// Display preferences, persisted in the App Group so widgets honor them.
/// Plain value type — widgets load it once per timeline; the app wraps it
/// in `PreferencesModel` for observation.
struct Preferences: Sendable {
    var displayMode: DisplayMode = .used
    var resetStyle: ResetStyle = .relative
    var refreshCadence: RefreshCadence = .minutes30
    var appearance: AppearanceMode = .system
    var modelSlotFallback: ModelSlotFallback = .auto
    /// Which single window the compact "at a glance" surfaces show: the
    /// Lock Screen circular gauge (room for exactly one number). Stored as a plain `UsageWindow.Kind`
    /// rather than a fixed enum so it scales to whatever the account
    /// actually reports — a per-model window (e.g. Fable on Max) or
    /// Credits, not just Session/Weekly.
    var glanceMetric: UsageWindow.Kind = .session
    /// Shows the Credits row's used/limit amounts in place of a reset
    /// line (a spend cap has no rollover date to show one). Off by
    /// default — opt-in extra detail, only visible when a Credits row is
    /// actually showing.
    var showCreditsAmount: Bool = false
    /// Bars turn yellow above 70 % used and red above 85 % (`UsageLevel`);
    /// off, every bar — widgets included —
    /// stays terracotta whatever the figure. On by default, so it loads through the presence check.
    var usageColors: Bool = true

    /// Whether refreshes also read the provider's public status page, so
    /// an outage shows as an incident instead of an account error. On by
    /// default — it is an anonymous GET of a public page, disclosed in
    /// Privacy & data — which means it must load through the presence
    /// check.
    var checksServiceStatus: Bool = true
    /// The account closest to a limit first, everywhere accounts are
    /// listed (`AccountOrder`); off, the registry's order, the user's own.
    var ordersByUrgency: Bool = false

    var lastScheduledAt: Date?

    nonisolated enum Keys {
        static let displayMode = "pref.displayMode"
        static let resetStyle = "pref.resetStyle"
        static let refreshCadence = "pref.refreshCadence"
        static let appearance = "pref.appearance"
        static let modelSlotFallback = "pref.modelSlotFallback"
        static let glanceMetric = "pref.glanceMetric"
        static let showCreditsAmount = "pref.showCreditsAmount"
        static let usageColors = "pref.usageColors"
        static let checksServiceStatus = "pref.checksServiceStatus"
        static let ordersByUrgency = "pref.ordersByUrgency"
        static let lastScheduledAt = "pref.lastScheduledAt"
    }

    static var groupDefaults: UserDefaults {
        UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
    }

    static func load(from defaults: UserDefaults = groupDefaults) -> Preferences {
        var prefs = Preferences()
        if let raw = defaults.string(forKey: Keys.displayMode), let value = DisplayMode(rawValue: raw) {
            prefs.displayMode = value
        }
        if let raw = defaults.string(forKey: Keys.resetStyle), let value = ResetStyle(rawValue: raw) {
            prefs.resetStyle = value
        }
        if let value = RefreshCadence(rawValue: defaults.integer(forKey: Keys.refreshCadence)) {
            prefs.refreshCadence = value
        }
        if let raw = defaults.string(forKey: Keys.appearance), let value = AppearanceMode(rawValue: raw) {
            prefs.appearance = value
        }
        if let raw = defaults.string(forKey: Keys.modelSlotFallback), let value = ModelSlotFallback(rawValue: raw) {
            prefs.modelSlotFallback = value
        }
        if let raw = defaults.string(forKey: Keys.glanceMetric), let value = UsageWindow.Kind(storageKey: raw) {
            prefs.glanceMetric = value
        }
        prefs.showCreditsAmount = defaults.bool(forKey: Keys.showCreditsAmount)
        prefs.usageColors = bool(defaults, Keys.usageColors, default: true)
        prefs.checksServiceStatus = bool(defaults, Keys.checksServiceStatus, default: true)
        prefs.ordersByUrgency = defaults.bool(forKey: Keys.ordersByUrgency)
        if let timestamp = defaults.object(forKey: Keys.lastScheduledAt) as? Date {
            prefs.lastScheduledAt = timestamp
        }
        return prefs
    }

    /// `UserDefaults.bool(forKey:)` reports `false` for a key that was never
    /// written, which silently flips any preference whose default is `true`
    /// for every install that upgrades without touching the setting. The
    /// presence check keeps the struct's own default authoritative until the
    /// user actually chooses.
    static func bool(_ defaults: UserDefaults, _ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    static func recordScheduled(_ date: Date = Date()) {
        groupDefaults.set(date, forKey: Keys.lastScheduledAt)
    }

}
