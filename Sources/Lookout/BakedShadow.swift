import AppKit
import SwiftUI

/// A rounded rectangle's or a circle's drop shadow, as `.shadow` draws it, blurred once and then stretched: put it
/// behind the shape with `.bakedShadow(...)`. The live window looks the same, but the window's picture for the opening
/// morph is much cheaper: `cacheDisplay` draws every `.shadow` on the CPU in a transparency layer the size of the
/// window, blurred, each time (a few milliseconds a shadow, however small), where a picture is just drawn.
///
/// The picture is the shadow alone, the shape left out of it. Along a side long enough for its two corners and their
/// blur, the picture is of a shape just that long, and only its middle point, the same all along, is stretched; a
/// shorter side is drawn at its own length (a picture per length, a few in all). Its colour is in the picture too,
/// since an `.opacity` on it would take a transparency layer of its own again: a colour that changes (a hover, a focus)
/// changes picture rather than fading, from one shade of a faint shadow to the next.
struct BakedShadow: View {
    enum Outline: Hashable {
        /// `RoundedRectangle(cornerRadius:style: .continuous)`.
        case rounded(CGFloat)
        case circle
        /// The same rounded rectangle's `strokeBorder(lineWidth:)` (a focus ring's glow).
        case ring(CGFloat, lineWidth: CGFloat)
    }

    var outline: Outline
    var color: Color
    var radius: CGFloat
    var y: CGFloat = 0

    @Environment(\.displayScale) private var scale

    /// How far the blur reaches past the shape, offset included: three times the radius covers what `.shadow` draws.
    private var margin: CGFloat { (radius * 3 + abs(y)).rounded(.up) }
    /// The part of the shape at each end of a side that the stretch leaves alone: a continuous corner (wider than its
    /// radius) and the blur's reach in from the edge.
    private var end: CGFloat {
        switch outline {
        case .rounded(let cornerRadius), .ring(let cornerRadius, _): (cornerRadius * 1.6).rounded(.up) + margin
        // Never stretched.
        case .circle: .infinity
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // Stretched along a side long enough, else drawn at the side's length.
            let width = size.width >= 2 * end + 1 ? nil : size.width
            let height = size.height >= 2 * end + 1 ? nil : size.height
            if let image = Self.image(Key(outline: outline, color: color, radius: radius, y: y, scale: scale, width: width,
                                          height: height), margin: margin, end: end) {
                let h = width == nil ? margin + end : 0, v = height == nil ? margin + end : 0
                Image(decorative: image, scale: scale)
                    .resizable(capInsets: EdgeInsets(top: v, leading: h, bottom: v, trailing: h), resizingMode: .stretch)
                    .padding(-margin)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct Key: Hashable {
        let outline: Outline
        let color: Color
        let radius, y, scale: CGFloat
        /// The side's own length when it is too short to stretch.
        let width, height: CGFloat?
    }

    @MainActor private static var cache: [Key: CGImage] = [:]

    @MainActor
    private static func image(_ key: Key, margin: CGFloat, end: CGFloat) -> CGImage? {
        if let image = cache[key] { return image }
        let width = key.width ?? 2 * end + 1, height = key.height ?? 2 * end + 1
        // The shape sits one picture to the left, out of it, and its shadow is moved back in.
        let away = width + 2 * margin
        let shape = switch key.outline {
        case .rounded(let cornerRadius): AnyView(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(.black))
        case .circle: AnyView(Circle().fill(.black))
        case .ring(let cornerRadius, let lineWidth):
            AnyView(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.black, lineWidth: lineWidth))
        }
        let picture = shape
            .frame(width: width, height: height)
            .shadow(color: key.color, radius: key.radius, x: away, y: key.y)
            .offset(x: -away)
            .frame(width: away, height: height + 2 * margin)
        let renderer = ImageRenderer(content: picture)
        renderer.scale = key.scale
        guard let image = renderer.cgImage else { return nil }
        cache[key] = image
        return image
    }
}

extension View {
    /// `.shadow(color:radius:y:)` for a single shape filled evenly (`fill`, or opaque when nil), drawn from a picture
    /// blurred once (see `BakedShadow`): `.shadow` takes the fill's opacity on top of the colour's.
    func bakedShadow(_ color: Color, _ outline: BakedShadow.Outline, radius: CGFloat, y: CGFloat = 0, fill: Color? = nil) -> some View {
        let opacity = fill.map { Double(NSColor($0).usingColorSpace(.sRGB)?.alphaComponent ?? 1) } ?? 1
        return background(BakedShadow(outline: outline, color: opacity < 1 ? color.opacity(opacity) : color, radius: radius, y: y))
    }
}
