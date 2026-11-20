import SwiftUI
import WidgetKit

/// A home screen widget's container background: the app's backdrop
/// gradient in full color. In the accented and vibrant modes the system
/// draws its own background, so nothing is drawn there.
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
