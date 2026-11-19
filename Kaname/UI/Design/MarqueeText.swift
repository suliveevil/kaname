import SwiftUI

/// A single-line label that scrolls sideways once while the pointer rests on its row, so a
/// command name clipped by the fixed shortcut column can still be read in full.
///
/// The scroll is a one-way trip, not a loop: it starts at the beginning, runs just far
/// enough for the last glyph to clear the clip edge, and then **stays there** for as long
/// as the pointer is on the row. There is no autoreverse, so the text never bounces back
/// and forth. Moving the pointer away stops the animation at once and restores the name to
/// its original position; re-entering starts a fresh trip from the beginning.
///
/// The available width comes from a `GeometryReader` around the view. An inner
/// `.frame(maxWidth: .infinity)` is not enough: the scrolling label is `fixedSize`, so that
/// frame grew to the label's natural width, the clip did nothing and the measured container
/// equalled the text — `hidden` was permanently zero and the marquee never started. Keeping
/// the GeometryReader's height at exactly one measured line gives it the same vertical
/// footprint as a plain `Text`, so the fixed columns and row heights do not move. A hidden
/// `Text` used as the layout view was tried too; its overlay scrolled but did not reliably
/// snap back when the pointer left.
///
/// The text is drawn in an explicitly sized, clipped frame and moved with `offset`; neither
/// participates in layout, so `RowLayout` and the paging arithmetic are untouched. A name
/// that fits never moves. The row supplies the full name to VoiceOver.
///
/// The row owns the hover state and passes it in; this view does not add a hit target or
/// an `onHover` of its own, so it cannot change which row the pointer is considered to be
/// over.
struct MarqueeText: View {
    let content: Text
    let isActive: Bool

    @State private var contentSize: CGSize = .zero

    /// A little room past the last glyph, so its right edge is not flush with the clip edge.
    private let tailSlack: CGFloat = 8
    private let pointsPerSecond: CGFloat = 36

    var body: some View {
        GeometryReader { proxy in
            let available = proxy.size.width
            let hidden = max(0, contentSize.width - available)
            // One-way distance. The slack is only added when something is actually hidden,
            // otherwise a name that fits would twitch sideways by a few points.
            let travel = hidden > 1 ? hidden + tailSlack : 0
            ZStack(alignment: .leading) {
                content
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
                    .background(
                        GeometryReader { inner in
                            Color.clear.preference(key: ContentSizeKey.self, value: inner.size)
                        }
                    )
                    .offset(x: isActive ? -travel : 0)
                    // A plain one-shot linear animation: it reaches `travel` and holds it.
                    // The zero-duration branch makes the reset on leave an instant snap.
                    .animation(
                        isActive && travel > 1
                            ? .linear(duration: Double(travel / pointsPerSecond))
                            : .linear(duration: 0),
                        value: MarqueeState(active: isActive, travel: travel)
                    )
                    .transaction { transaction in
                        // Leaving mid-scroll cancels the in-flight animation rather than
                        // letting it coast on to a target the row no longer owns.
                        if !isActive { transaction.disablesAnimations = true }
                    }
            }
            .frame(width: available, height: proxy.size.height, alignment: .leading)
            .clipped()
        }
        // Exactly one line tall, whatever height the row proposes. A bare GeometryReader is
        // flexible in both axes and would otherwise stretch a two-line search result.
        .frame(height: contentSize.height)
        .onPreferenceChange(ContentSizeKey.self) { contentSize = $0 }
        .accessibilityHidden(true)
    }
}

/// Changing either value re-targets the animation: activating starts a fresh trip, leaving
/// resets it, and a panel resize recomputes the distance without changing the row geometry.
private struct MarqueeState: Equatable {
    let active: Bool
    let travel: CGFloat
}

private struct ContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
