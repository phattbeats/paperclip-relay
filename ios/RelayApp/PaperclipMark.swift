import SwiftUI

/// The board's own paperclip mark, and the animation it draws itself with.
///
/// The geometry is the board's, taken from the mark in the deployed web
/// app rather than redrawn: the same path, the same dash length, and the
/// same three keyframes. An app that opens on a different logo than the
/// board it fronts is a small lie about what it is.
///
/// The path, in the board's own 24×24 space:
///
///     M16 6 l-8.414 8.586 a2 2 0 0 0 2.828 2.828 l8.414 -8.586
///     a4 4 0 1 0 -5.657 -5.657 l-8.379 8.551 a6 6 0 1 0 8.485 8.485
///     l8.379 -8.551
///
/// The arcs are drawn as explicit cubic segments rather than with
/// `Path.addArc`, so the curve is the board's curve and not whatever an arc
/// approximation happens to produce on the day.
struct PaperclipShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let offsetX = (rect.width - 24 * scale) / 2
        let offsetY = (rect.height - 24 * scale) / 2

        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: offsetX + CGFloat(x) * scale, y: offsetY + CGFloat(y) * scale)
        }

        var path = Path()
        path.move(to: point(16, 6))

        // Down-left to the first bend.
        path.addLine(to: point(7.586, 14.586))
        addArc(to: &path,
               center: point(9.0123, 15.9877),
               radius: CGFloat(2.0 * scale),
               start: -135.498,
               end: -314.502)

        // Up-right past the top of the mark.
        path.addLine(to: point(18.828, 8.828))
        addArc(to: &path,
               center: point(15.9995, 5.9995),
               radius: CGFloat(4.0001 * scale),
               start: 45,
               end: -135)

        // Down-left to the outermost bend.
        path.addLine(to: point(4.792, 11.722))
        addArc(to: &path,
               center: point(9.0287, 15.9703),
               radius: CGFloat(6.0 * scale),
               start: -134.922,
               end: -315.078)

        // And back up to the open end.
        path.addLine(to: point(21.656, 11.656))
        return path
    }

    /// Append a circular arc, travelling from `start` to `end` in the
    /// decreasing direction.
    ///
    /// Angles are degrees in the path's own space, measured from the
    /// positive x-axis; the y axis points down, as it does in the board's
    /// SVG. The decreasing direction is the one the board's path takes, so
    /// the bends face the way they face on the board.
    private func addArc(to path: inout Path,
                        center: CGPoint,
                        radius: CGFloat,
                        start: Double,
                        end: Double) {
        let sweep = end - start
        let segments = max(1, Int(ceil(abs(sweep) / 90)))
        let step = sweep / Double(segments)
        // The cubic approximation of a circular arc: the handle is
        // (4/3)·tan(Δθ/4)·r, and it keeps the sign of the sweep so the
        // control points fall on the side the curve actually bulges.
        let handle = 4.0 / 3.0 * tan(step * .pi / 180 / 4)

        func point(_ angle: Double) -> CGPoint {
            let radians = angle * .pi / 180
            return CGPoint(x: center.x + radius * CGFloat(cos(radians)),
                           y: center.y + radius * CGFloat(sin(radians)))
        }

        /// The outward normal at an angle — the direction the arc's
        /// control points sit on.
        func normal(_ angle: Double) -> CGPoint {
            let radians = angle * .pi / 180
            return CGPoint(x: CGFloat(-sin(radians)), y: CGFloat(cos(radians)))
        }

        var current = start
        for _ in 0..<segments {
            let next = current + step
            let startPoint = point(current)
            let endPoint = point(next)
            let startNormal = normal(current)
            let endNormal = normal(next)
            path.addCurve(to: endPoint,
                          control1: CGPoint(x: startPoint.x + CGFloat(handle) * radius * startNormal.x,
                                            y: startPoint.y + CGFloat(handle) * radius * startNormal.y),
                          control2: CGPoint(x: endPoint.x - CGFloat(handle) * radius * endNormal.x,
                                            y: endPoint.y - CGFloat(handle) * radius * endNormal.y))
            current = next
        }
    }
}

/// The animation timing, taken from the board's stylesheet.
///
///     @keyframes paperclip-thinking-draw {
///       0%      { stroke-dasharray: 0 85.717; stroke-dashoffset: -85.717px;
///                  animation-timing-function: cubic-bezier(.455,.03,.515,.955) }
///       39.0625%{ stroke-dasharray: 85.717 85.717; stroke-dashoffset: 0;
///                  animation-timing-function: cubic-bezier(.55,.055,.675,.19) }
///       78.125%{ stroke-dasharray: 0 85.717; stroke-dashoffset: 0 }
///     }
///     .paperclip-thinking-icon-path { animation: 1s linear infinite … }
///
/// So: draw over the first 39% of the loop, erase over the next 39%, and
/// sit blank for the last 22%. The two eases are CSS cubic-beziers, which
/// are reproduced here rather than approximated with a stock curve.
enum PaperclipMark {
    /// The dash length the board's own stylesheet uses.
    static let dashLength: Double = 85.717

    /// Where the drawing stops and the erasing starts.
    static let revealEnd: Double = 0.390625

    /// Where the erasing stops.
    static let eraseEnd: Double = 0.78125

    /// How much of the path is drawn at a point in the one-second loop.
    static func trim(at phase: Double) -> CGFloat {
        if phase < revealEnd {
            let eased = CubicBezier(x1: 0.455, y1: 0.03, x2: 0.515, y2: 0.955)
                .value(phase / revealEnd)
            return CGFloat(eased)
        }
        if phase < eraseEnd {
            let eased = CubicBezier(x1: 0.55, y1: 0.055, x2: 0.675, y2: 0.19)
                .value((phase - revealEnd) / (eraseEnd - revealEnd))
            return CGFloat(1 - eased)
        }
        return 0
    }
}

/// A CSS-style cubic bezier easing curve.
struct CubicBezier {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double

    func value(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }

        // Newton-Raphson, with a bisection fallback for the flat parts of
        // the curve where the derivative goes to zero.
        var t = x
        for _ in 0..<8 {
            let error = sampleX(t) - x
            if abs(error) < 1e-7 { return sampleY(t) }
            let slope = sampleDerivative(t)
            if abs(slope) < 1e-7 { break }
            t -= error / slope
        }

        var low = 0.0
        var high = 1.0
        t = x
        while high - low > 1e-7 {
            if sampleX(t) < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return sampleY(t)
    }

    private func sampleX(_ t: Double) -> Double {
        let inverse = 1 - t
        return 3 * inverse * inverse * t * x1
            + 3 * inverse * t * t * x2
            + t * t * t
    }

    private func sampleY(_ t: Double) -> Double {
        let inverse = 1 - t
        return 3 * inverse * inverse * t * y1
            + 3 * inverse * t * t * y2
            + t * t * t
    }

    private func sampleDerivative(_ t: Double) -> Double {
        let inverse = 1 - t
        return 3 * inverse * inverse * x1
            + 6 * inverse * t * (x2 - x1)
            + 3 * t * t * (1 - x2)
    }
}

/// The mark, drawing itself on a one-second loop.
struct PaperclipSplashView: View {
    var size: CGFloat = 88
    var lineWidth: CGFloat = 3

    /// Anchor the loop to this instance, rather than the wall clock, so a
    /// fresh launch always begins at the board's zero-length keyframe.
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSince(startedAt)
                .truncatingRemainder(dividingBy: 1.0)
            PaperclipShape()
                .trim(from: 0, to: PaperclipMark.trim(at: phase))
                .stroke(style: StrokeStyle(lineWidth: lineWidth,
                                           lineCap: .round,
                                           lineJoin: .round))
                .frame(width: size, height: size)
                .foregroundColor(Color.accentColor)
        }
        .accessibilityHidden(true)
    }
}
