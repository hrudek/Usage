import Foundation
import Observation
import UsageKit
import WidgetKit

/// Observable wrapper used by the app; every change writes through to the
/// App Group immediately. One stored `Preferences` value behind computed
/// accessors, so the field list exists once (`Preferences` itself) rather
/// than being repeated here in the properties, the initializer, and a
/// snapshot builder; `@Observable` tracks reads and writes through the
/// stored value, which is all the bindings need. Every setter skips a
/// write of the value already held: with one stored struct, any write
/// invalidates every reader of every field, and a scene that writes its
/// binding back during body evaluation (`MenuBarExtra(isInserted:)`)
/// would otherwise re-evaluate the App body forever — a launch crash by
/// stack overflow. The guard also keeps no-op writes from reloading
/// widget timelines.
@Observable
final class PreferencesModel {
    private var stored: Preferences
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var widgetReload: Task<Void, Never>?

    init(defaults: UserDefaults = Preferences.groupDefaults) {
        self.defaults = defaults
        stored = Preferences.load(from: defaults)
    }

    var displayMode: DisplayMode {
        get { stored.displayMode }
        set { guard stored.displayMode != newValue else { return }; stored.displayMode = newValue; persist(newValue.rawValue, Preferences.Keys.displayMode, reloadsWidgets: true) }
    }
    var resetStyle: ResetStyle {
        get { stored.resetStyle }
        set { guard stored.resetStyle != newValue else { return }; stored.resetStyle = newValue; persist(newValue.rawValue, Preferences.Keys.resetStyle, reloadsWidgets: true) }
    }
    var refreshCadence: RefreshCadence {
        get { stored.refreshCadence }
        set { guard stored.refreshCadence != newValue else { return }; stored.refreshCadence = newValue; persist(newValue.rawValue, Preferences.Keys.refreshCadence, reloadsWidgets: true) }
    }
    var appearance: AppearanceMode {
        get { stored.appearance }
        set { guard stored.appearance != newValue else { return }; stored.appearance = newValue; persist(newValue.rawValue, Preferences.Keys.appearance, reloadsWidgets: false) }
    }
    var modelSlotFallback: ModelSlotFallback {
        get { stored.modelSlotFallback }
        set { guard stored.modelSlotFallback != newValue else { return }; stored.modelSlotFallback = newValue; persist(newValue.rawValue, Preferences.Keys.modelSlotFallback, reloadsWidgets: true) }
    }
    var glanceMetric: UsageWindow.Kind {
        get { stored.glanceMetric }
        set { guard stored.glanceMetric != newValue else { return }; stored.glanceMetric = newValue; persist(newValue.storageKey, Preferences.Keys.glanceMetric, reloadsWidgets: true) }
    }
    var showCreditsAmount: Bool {
        get { stored.showCreditsAmount }
        set { guard stored.showCreditsAmount != newValue else { return }; stored.showCreditsAmount = newValue; persist(newValue, Preferences.Keys.showCreditsAmount, reloadsWidgets: true) }
    }
    var usageColors: Bool {
        get { stored.usageColors }
        set { guard stored.usageColors != newValue else { return }; stored.usageColors = newValue; persist(newValue, Preferences.Keys.usageColors, reloadsWidgets: true) }
    }
    var ordersByUrgency: Bool {
        get { stored.ordersByUrgency }
        set { guard stored.ordersByUrgency != newValue else { return }; stored.ordersByUrgency = newValue; persist(newValue, Preferences.Keys.ordersByUrgency, reloadsWidgets: true) }
    }

    var lastScheduledAt: Date? {
        defaults.object(forKey: Preferences.Keys.lastScheduledAt) as? Date
    }

    func toggleResetStyle() {
        resetStyle = resetStyle == .relative ? .absolute : .relative
    }



    /// The current values as a plain `Preferences`, for code paths written
    /// against the value type (widgets' rendering helpers).
    var snapshot: Preferences {
        var prefs = stored
        prefs.lastScheduledAt = lastScheduledAt
        return prefs
    }

    /// Writes one key through to the App Group. `reloadsWidgets` is true
    /// for the prefs widgets read when they render: nothing re-renders
    /// them until their next timeline reload, up to the refresh floor
    /// away, so one
    /// coalesced reload per burst of changes (a segmented pill tapped three
    /// times in a row is one reload, not three against WidgetKit's per-kind
    /// budget) closes that gap.
    private func persist(_ value: Any?, _ key: String, reloadsWidgets: Bool) {
        defaults.set(value, forKey: key)
        guard reloadsWidgets else { return }
        widgetReload?.cancel()
        widgetReload = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            WidgetReload.all()
        }
    }
}
