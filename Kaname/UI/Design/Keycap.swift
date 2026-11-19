import SwiftUI

/// The chrome that makes one key read as a physical keycap — a tinted rounded square,
/// hairline border and lower edge, the way an HTML `<kbd>` element draws.
///
/// The caller owns the square frame; this modifier only paints the face, so a key's size is
/// declared once in `KeycapSequence.edge`. Five 20 pt keys with four 3 pt gaps need 112 pt,
/// which is why `RowLayout` widened the symbols slot from 70 pt to 116 pt and the search and
/// statistics columns from 78/76 pt to 116 pt. The header's 600/460 thresholds still assume
/// four 20 pt chips. `horizontalSpread` / `verticalSpread` remain for callers that need the
/// face to grow outside a frame without changing layout.
///
/// `enabled` lets a call site opt out without a second copy of the view — the dash standing
/// in for a missing shortcut is not a key, and a prose hint is not a chord.
struct KeycapChrome: ViewModifier {
    var fill: Color
    var border: Color
    var cornerRadius: CGFloat = Theme.radiusControl
    var horizontalSpread: CGFloat = 0
    var verticalSpread: CGFloat = 0
    var lineWidth: CGFloat = 0.5
    var enabled = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.background(face)
        } else {
            content
        }
    }

    private var face: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border, lineWidth: lineWidth)
            )
            // A one-point lower edge is what separates a keycap from a plain badge.
            .shadow(color: border.opacity(0.6), radius: 0, x: 0, y: 1)
            .padding(.horizontal, -horizontalSpread)
            .padding(.vertical, -verticalSpread)
            .decorative()
    }
}

/// A chord drawn as one `<kbd>` per key, not as a single badge around the whole string.
///
/// Tokens come from a rendered chord string because some callers only have the string (the
/// breadcrumb and the settings keycaps). A modifier glyph, a special glyph and a whole
/// alphanumeric key name (`F5`, `Return`, `cmd`) each become one token; whitespace and the
/// words-style `+` separators are dropped and replaced by `gap`. Each token gets a square
/// frame, so the widest symbols chord (`⌃⌥⇧⌘Q`) is 5 × 20 + 4 × 3 = 112 pt and fits the
/// 116 pt column with a clear gap between every pair of keys.
struct KeycapSequence: View {
    let text: String
    var font: Font = .system(size: TypeScale.body, weight: .bold, design: .rounded)
    var foreground: Color = .primary
    var fill: Color = Color.primary.opacity(0.10)
    var border: Color = Color.primary.opacity(0.18)
    var cornerRadius: CGFloat = Theme.radiusTag
    /// One key is a rounded square, not a capsule hugging the glyph. The frame is the
    /// layout cost: five 20 pt keys with 3 pt gaps need 112 pt, which is why the chord
    /// columns were widened from 70/78/76 pt to 116 pt.
    var edge: CGFloat = 20
    var gap: CGFloat = 3
    var enabled = true

    var body: some View {
        HStack(spacing: enabled ? gap : 0) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                Text(token)
                    .font(font)
                    .monospacedDigit()
                    .foregroundStyle(foreground)
                    // A key name longer than a glyph (`F5`, `Return`) widens its own cap
                    // instead of being clipped, so those keys are rounded rectangles.
                    .frame(minWidth: enabled ? edge : 0, minHeight: enabled ? edge : 0)
                    .keycap(
                        fill: fill,
                        border: border,
                        cornerRadius: cornerRadius,
                        horizontalSpread: 0,
                        verticalSpread: 0,
                        enabled: enabled
                    )
            }
        }
        .lineLimit(1)
    }

    private var tokens: [String] {
        guard enabled else { return [text] }
        return Self.split(text)
    }

    /// Splits a rendered chord into individual keys. Consecutive ASCII letters/digits stay
    /// together so `F5` and `cmd` are one key, while every other glyph stands alone.
    static func split(_ text: String) -> [String] {
        var result: [String] = []
        var word = ""
        func flush() {
            if !word.isEmpty {
                result.append(word)
                word = ""
            }
        }
        for character in text {
            if character.isWhitespace || character == "+" {
                flush()
            } else if character.isASCII, character.isLetter || character.isNumber {
                word.append(character)
            } else {
                flush()
                result.append(String(character))
            }
        }
        flush()
        return result.isEmpty ? [text] : result
    }
}

extension View {
    /// Applies the shared keycap chrome. Colours come from the caller because the panel
    /// can be forced light or dark independently of the system appearance, where
    /// `Color.primary` would put black paint on a graphite surface.
    func keycap(
        fill: Color,
        border: Color,
        cornerRadius: CGFloat = Theme.radiusControl,
        horizontalSpread: CGFloat = 0,
        verticalSpread: CGFloat = 0,
        lineWidth: CGFloat = 0.5,
        enabled: Bool = true
    ) -> some View {
        modifier(
            KeycapChrome(
                fill: fill,
                border: border,
                cornerRadius: cornerRadius,
                horizontalSpread: horizontalSpread,
                verticalSpread: verticalSpread,
                lineWidth: lineWidth,
                enabled: enabled
            )
        )
    }
}
