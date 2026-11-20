import SwiftUI
import WidgetKit

/// The home screen widgets' backdrop: the app's gradient in full color,
/// nothing in the accented and vibrant modes, where the system draws its
/// own background.
///
/// The gradient uses plain sRGB colors for the widget's color scheme
/// rather than `Theme.backdrop`'s trait-resolved ones.
struct WidgetBackdrop: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if renderingMode == .fullColor {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: scheme == .dark ? 0x2B2D42 : 0xFCFBF8), location: 0),
                    .init(color: Color(hex: scheme == .dark ? 0x0D0E14 : 0xF3F1EA), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color.clear
        }
    }
}

/// Draws `WidgetBackdrop` as the container background and again behind
/// the content. On device the container background alone rendered lighter
/// than the same gradient in a Scriptable widget; the copy in the content
/// layer tests whether the system lightens only the container layer.
/// Where the system hides the container background (StandBy), the
/// content copy is left out too.
private struct WidgetBackdropModifier: ViewModifier {
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    func body(content: Content) -> some View {
        Group {
            if showsBackground {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { WidgetBackdrop() }
            } else {
                content
            }
        }
        .containerBackground(for: .widget) {
                WidgetBackdrop()
            }
    }
}

extension View {
    func widgetBackdrop() -> some View {
        modifier(WidgetBackdropModifier())
    }
}
