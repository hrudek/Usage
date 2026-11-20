import SwiftUI
import WidgetKit

/// A home screen widget's container background: `Theme.backdrop` in full
/// color. In the accented and vibrant modes the system draws its own
/// background, so nothing is drawn there.
struct WidgetBackdrop: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if renderingMode == .fullColor {
            Theme.backdrop
        } else {
            Color.clear
        }
    }
}
