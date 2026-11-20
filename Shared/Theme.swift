import SwiftUI

/// Usage design tokens — single source of truth for app and widgets.
enum Theme {
    // MARK: - Palette (all colors adapt to light/dark)

    static let accent = Color(light: 0x387963, dark: 0x5DCAA5)
    /// Soft accent wash for pills, selected segments, icon chips.
    static let accentWash = accent.opacity(0.14)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0D0E14)
    /// Warm yellow for usage above 70 % or provider-flagged warning —
    /// clearly yellow, with enough warmth to sit with the accent on
    /// ivory and charcoal cards (a cold, pure yellow glared on a light
    /// widget).
    static let warning = Color(light: 0xDDA712, dark: 0xF0BF3A)
    /// The warning yellow on pure black.
    static let islandWarning = Color(hex: 0xF5C443)
    static let danger = Color(light: 0xC24040, dark: 0xE24B4A)

    static let backgroundStart = Color(light: 0xFCFBF8, dark: 0x2B2D42)
    static let backgroundEnd = Color(light: 0xF3F1EA, dark: 0x0D0E14)
    static let backdrop = LinearGradient(
        colors: [backgroundStart, backgroundEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    /// Card surface.
    static let card = Color(light: 0xFFFFFF, dark: 0x2B2D42)
    /// Progress bar track and hairlines: warm paper.
    static let track = Color(light: 0xEDEAE1, dark: 0x3A3D52)

    /// Primary text: warm near-black / warm ivory.
    static let ink = Color(light: 0x1F1E1D, dark: 0xFFFFFF)
    /// Secondary text (reset lines, footers, captions).
    static let inkSecondary = Color(light: 0x87867F, dark: 0x8D99AE)

    // MARK: - Typography

    /// Section headers ("Claude", "Display", "Rate limits").
    static let sectionHeader = Font.subheadline.weight(.medium)
    /// Window name in a usage row ("5-hour session").
    static let rowTitle = Font.body.weight(.medium)
    /// Percentage next to a bar — always monospaced digits.
    static let percent = Font.body.monospacedDigit().weight(.semibold)
    /// Reset line, "Updated X ago", footnotes.
    static let caption = Font.footnote
    /// Every usage figure, everywhere (4.0): the account card's
    /// protagonist, every widget.
    /// Rounded, with tabular digits so a changing figure doesn't jitter.
    /// The app passes its own `@ScaledMetric` so it follows Dynamic Type;
    /// widgets pass fixed sizes (see `WidgetHeader`).
    static func figure(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
    /// A compact row's percentage on an account card.
    static let compactPercent = Font.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit()

    // MARK: - Elevation

    /// Wide, diffuse drop shadow under cards — the soft "glass float"
    /// elevation. Pair with `shadowTight` for a grounded edge.
    static let shadowSoft = Color.black.opacity(0.07)
    /// Tight contact shadow that grounds the card edge.
    static let shadowTight = Color.black.opacity(0.04)
    /// The light along a card's top edge, fading down its sides: what
    /// makes a surface read as a pane rather than a printed box.
    static func edgeLight(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.11) : .white.opacity(0.95)
    }
    /// The hairline that closes a card's lower edge.
    static func edgeShade(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .black.opacity(0.35) : Color(hex: 0x1F1E1D).opacity(0.07)
    }

    // MARK: - Metrics

    /// Card corner radius (continuous).
    static let cardRadius: CGFloat = 24
    /// Inner padding of cards.
    static let cardPadding: CGFloat = 16
    /// Progress bar height (capsule).
    static let barHeight: CGFloat = 6
    /// Vertical gap between sections.
    static let sectionSpacing: CGFloat = 24
    /// Vertical gap between rows inside a card.
    static let rowSpacing: CGFloat = 14
}

extension Color {
    /// Dynamic color from light/dark hex values (0xRRGGBB).
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
