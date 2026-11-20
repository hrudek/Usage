import SwiftUI
import AppIntents

/// Puts back the system's content margins that every widget configuration
/// turns off (`contentMarginsDisabled`), so a button can reach the edges.
private struct WidgetMargins: ViewModifier {
    @Environment(\.widgetContentMargins) private var margins

    func body(content: Content) -> some View {
        content.padding(margins)
    }
}

extension View {
    /// The system margins as padding, for content outside the tap button.
    func widgetMargins() -> some View {
        modifier(WidgetMargins())
    }

    /// The whole widget surface, edges included, is one button that runs
    /// `intent` (a refresh) instead of opening the app. Plain style, so
    /// nothing is restyled; the margins are padding inside the button, so
    /// the layout is the system's.
    func refreshesOnTap<I: AppIntent>(_ intent: I) -> some View {
        Button(intent: intent) {
            widgetMargins()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Refresh"))
    }
}
