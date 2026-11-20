import Foundation
import UsageKit

/// The macOS-only plumbing that keeps the model refreshing with no window
/// open: the `NSBackgroundActivityScheduler` cadence and the wake /
/// activation observers. See the type doc in `UsageModel.swift`.
extension UsageModel {
    // MARK: - macOS refresh schedule

}

/// Lets the background refresh schedule, the wake observer and the App
/// Intents reach the live model from code that can't capture it strongly
/// — set once in `UsageModel.init` for the app's own model, on both
/// platforms.
enum AppEnvironment {
    static weak var shared: UsageModel?
    /// The app's one `PreferencesModel`, published by the dashboard scene
    /// on appear (`AIMeterApp`) for the notch island, which lives outside
    /// the scene graph and has no environment to read it from, and for
    /// iCloud sync, which applies another device's preferences through it
    /// on both platforms.
    static weak var prefs: PreferencesModel?
}
