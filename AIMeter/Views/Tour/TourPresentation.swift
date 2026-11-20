import SwiftUI

/// The tour over the whole screen, at the first launch and from Settings:
/// the step at the top and its buttons at the bottom, scrolling only where
/// a large text size makes it taller than the screen.
struct TourCover: View {
    let finish: (_ connect: Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                TourView(finish: finish)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .appBackground()
    }
}

/// Settings' "Show the tour": the full tour again, whatever was turned on
/// since. On iOS it opens once the Settings sheet is gone
/// (`Tour.deliverPendingShow`).
struct TourSettings: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Card {
            Button {
                Tour.showRequested = true
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28, height: 28)
                        .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text("Show the tour")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        SectionFootnote(text: String(localized: "What each part of AIMeter does, one at a time, with a button to turn it on."))
    }
}
