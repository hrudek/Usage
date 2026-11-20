import SwiftUI
import UsageKit

struct ProviderMark: View {
    let size: CGFloat
    let cornerRadius: CGFloat
    /// The account's chosen glyph; nil draws the default.
    var icon: AccountIcon? = nil
    /// Filled tile with an on-accent glyph for a sheet-sized header; every inline
    /// header uses the quieter wash + accent glyph the rest of the app's
    /// icon tiles already use (Settings rows, Privacy rows).
    var prominent: Bool = false

    var body: some View {
        Group {
            switch icon {
            case .mark(let mark):
                tile {
                    Image(Self.assetName(for: mark))
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 0.55, height: size * 0.55)
                }
            case .symbol(let name):
                tile {
                    Image(systemName: name)
                        .font(.system(size: size * 0.55, weight: .semibold))
                }
            case nil:
                tile {
                    Image(systemName: Self.defaultSymbol)
                        .font(.system(size: size * 0.55, weight: .semibold))
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// The glyph every account starts with.
    nonisolated static let defaultSymbol = "sparkle"

    static func assetName(for mark: AccountIcon.Mark) -> String {
        switch mark {
        case .claude: return "ClaudeMark"
        case .claudeCode: return "ClaudeCodeMark"
        case .openAI: return "OpenAIMark"
        }
    }

    private func tile<Glyph: View>(@ViewBuilder _ glyph: () -> Glyph) -> some View {
        glyph()
            .foregroundStyle(prominent ? Theme.onAccent : Theme.accent)
            .frame(width: size, height: size)
            .background(
                prominent ? Theme.accent : Theme.accentWash,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}
