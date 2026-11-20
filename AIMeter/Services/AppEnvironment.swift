import Foundation
import UsageKit

/// Lets the background refresh and the App Intents reach the live model
/// from code that can't capture it strongly — set once in
/// `UsageModel.init` for the app's own model.
enum AppEnvironment {
    static weak var shared: UsageModel?
}
