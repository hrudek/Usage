import SwiftUI
import WidgetKit

/// A home screen widget's container background: the app's backdrop
/// gradient in full color. In the accented and vibrant modes the system
/// draws its own background, so nothing is drawn there.
///
/// The gradient is built from plain sRGB colors for the widget's own color
/// scheme, with explicit stops at 0 and 1, instead of `Theme.backdrop`'s
/// trait-resolved `UIColor` closures. The same two colors rendered
/// lighter and flatter than Scriptable's on device (needs a device check:
/// the cause is not provable without one), so the fixed colors remove the
/// one thing in the widget path that depends on trait resolution.
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
