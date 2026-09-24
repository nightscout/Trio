import Foundation
import SwiftUI

/// The glucose readings themselves: one `Canvas` pass, drawn by the shell.
///
/// These were one `PointMark` per reading inside the canvas chart, drawn by this same type.
/// Swift Charts gives every mark its own identity, scale resolution, style
/// resolution and layout pass, and the series runs to ~900 marks at 24 h zoom over the 72 h
/// history — so a committed zoom re-layout, which happens several times per pinch, spent most
/// of its time on marks that draw a 5 pt circle. Every reading is still drawn; it just costs a
/// `context.fill` instead of a mark. The same move — a rasterized path in place of a view per
/// data point — is what made the treatment markers affordable; see `TreatmentTriangleSymbol`.
///
/// Drawing the readings here is also what lets the series be handed around whole. While they
/// were marks they had to be culled to the visible window to keep the layout affordable, and
/// that moving slice is what made the treatment anchors unstable — see
/// `MainChartHelper.nearestDot`. This layer culls inside its own draw loop instead, so
/// nothing upstream of it ever sees a slice.
struct GlucoseChartView: View {
    /// Ascending, and covering the whole domain — this layer culls to the visible window itself.
    let points: [MainChartHelper.GlucoseDot]
    let isSmoothingEnabled: Bool

    /// Time-to-x mapping for this frame, handed down by `ChartOverlayLayer` — already
    /// interpolated, and already carrying the live-pinch stretch.
    let viewport: ChartViewport

    /// Value-to-pixel mapping for the glucose pane, passed in so the dots, the treatment
    /// markers hanging off them and the selection highlight can never disagree.
    let yPosition: (Decimal) -> CGFloat

    /// Diameter of a reading's dot. `PointMark.symbolSize` is an *area* in square points, so
    /// the 20 the chart marks carried is recovered as a diameter here rather than hardcoded —
    /// the dots stay exactly the size they have always been.
    private static let dotDiameter: CGFloat = 2 * sqrt(20 / .pi)

    /// Width of the smoothed curve: Swift Charts' own default `LineMark` stroke.
    private static let smoothedLineWidth: CGFloat = 2

    /// How far beyond the visible window a dot is still drawn.
    private static let cullMarginPoints: CGFloat = 12

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            let visible = visiblePoints
            // Under the dots, as it was when both were marks in one chart.
            if isSmoothingEnabled {
                strokeSmoothedCurve(visible, into: &context)
            }
            drawDots(visible, into: &context)
        }
    }

    // MARK: - Drawing

    private func drawDots(_ visible: [MainChartHelper.GlucoseDot], into context: inout GraphicsContext) {
        let diameter = Self.dotDiameter
        // Resolved once per pass, and only when a manual reading is actually on screen.
        var manualSymbol: GraphicsContext.ResolvedText?

        for point in visible {
            let x = viewport.x(for: point.date)
            let y = yPosition(point.value)

            if point.isManual {
                let symbol = manualSymbol ?? context.resolve(
                    Text(Image(systemName: "drop.fill")).font(.caption2).bold().foregroundStyle(.red)
                )
                manualSymbol = symbol
                context.draw(symbol, at: CGPoint(x: x, y: y), anchor: .center)
            } else {
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: x - diameter / 2,
                        y: y - diameter / 2,
                        width: diameter,
                        height: diameter
                    )),
                    with: .color(point.color)
                )
            }
        }
    }

    /// The smoothed curve, as one stroked path. Readings without a smoothed value break it,
    /// exactly as they broke the old `LineMark` series.
    private func strokeSmoothedCurve(_ visible: [MainChartHelper.GlucoseDot], into context: inout GraphicsContext) {
        var path = Path()
        var started = false
        for point in visible {
            guard let smoothed = point.smoothed else {
                started = false
                continue
            }
            let location = CGPoint(x: viewport.x(for: point.date), y: yPosition(smoothed))
            if started {
                path.addLine(to: location)
            } else {
                path.move(to: location)
                started = true
            }
        }
        guard !path.isEmpty else { return }
        context.stroke(path, with: .color(Color.secondary), lineWidth: Self.smoothedLineWidth)
    }

    // MARK: - Culling

    /// The readings on screen, plus a margin. The 300 s slack is one reading at the CGM
    /// cadence: the smoothed curve has to reach the reading just outside the viewport, or it
    /// stops short of the edge instead of running off it.
    ///
    /// Only the drawing is culled here. The anchors the treatment markers search are the
    /// whole series, so this slice cannot move an anchor the way the old layout window did.
    private var visiblePoints: [MainChartHelper.GlucoseDot] {
        let range = viewport.cullRange(marginPoints: Self.cullMarginPoints, minimumSlack: 300)
        return MainChartHelper.windowSlice(
            points,
            from: range.lowerBound,
            through: range.upperBound,
            ascending: true,
            date: { $0.date }
        )
    }
}
