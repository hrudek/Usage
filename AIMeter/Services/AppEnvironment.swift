import Foundation
import UsageKit

/// Lets the background refresh schedule, the wake observer and the App
/// Intents reach the live model from code that can't capture it strongly
/// — set once in `UsageModel.init` for the app's own model, on both
/// platforms.
enum AppEnvironment {
    static weak var shared: UsageModel?
    /// The app's one `PreferencesModel`, published by `AIMeterApp` for code
    /// outside the scene graph.
    static weak var prefs: PreferencesModel?
}
