import SwiftUI
import AppIntents
import UsageKit

enum WidgetMetrics {
    /// The provider mark in a header's top-right corner.
    static let markSize: CGFloat = 24
    static let markRadius: CGFloat = 5.5
}

extension View {
    /// The whole widget is one button that runs `intent` (a refresh)
    /// instead of opening the app. Plain style, so nothing is restyled; the
    /// content keeps its own VoiceOver elements and the button is named.
    func refreshesOnTap<I: AppIntent>(_ intent: I) -> some View {
        Button(intent: intent) {
            frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Refresh"))
    }
}
