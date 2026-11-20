import SwiftUI

extension View {
    /// The app's two models, handed to a sheet's or a cover's content by its
    /// presenter rather than left to inheritance, which has crashed a
    /// sheet's first read of `UsageModel` (4.3.0).
    func withAppModels(_ model: UsageModel, _ prefs: PreferencesModel) -> some View {
        environment(model)
            .environment(prefs)
    }
}
