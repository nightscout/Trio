import Foundation
import SwiftUI

/// Treatment markers — boluses, carb entries and FPUs — with their dose and gram labels.
///
/// These used to be `PointMark`s inside the chart canvas; they are drawn by the shell now
/// for two reasons.
///
/// **Layout.** Swift Charts gives every mark its own identity, scale resolution, style
/// resolution and layout pass, and there is no way to add or remove one without re-laying the
/// whole chart — so culling to the visible window meant a full re-layout of the glucose curve
/// and the forecast every few percent of a viewport panned. Here a marker is a `context.fill`
/// in a draw loop, so culling costs nothing and there is no layout to re-run at all.
///
/// **Pinch.** A live pinch previews the zoom by applying `.scaleEffect(x:y:)` to the whole
/// canvas, an x-only transform. That is right for the glucose line and the basal bars, where
/// the gap between two timestamps genuinely does stretch, and wrong for anything with a fixed
/// point size — the triangles came out skewed, the dose text came out stretched, and both
/// snapped back at every zoom commit. Out here the pinch reaches their *coordinates* (through
/// `ChartViewport.x(for:)`, which applies the same transform) and nothing else, so a marker
/// holds its own shape for the whole gesture and there is nothing to snap back from.
///
/// One `Canvas` rather than a view per marker. This layer has no `Equatable` shortcut — it
/// redraws on every pan and pinch frame — so what it draws has to be cheap and bounded: it
/// culls to the visible window, which at any zoom is a few hundred markers rather than the
/// several thousand the canvas's own render window spans.
///
/// The frame, the hit testing and the animated-scroll interpolation belong to the
/// `ChartOverlayLayer` this is drawn inside; everything here works off the `viewport` it is
/// handed.
struct TreatmentOverlay: View {
    /// Ascending, and covering at least the visible window. Boluses and carbs hang off the
    /// curve, so this is also what their y anchor is looked up in. Pre-resolved values rather
    /// than `GlucoseStored`, so the per-frame lookups below touch no Core Data — ~900 readings
    /// at the widest zoom would otherwise be that many KVC hits every frame.
    let anchors: [MainChartHelper.GlucoseAnchor]
    let insulin: [PumpEventStored]
    let carbs: [CarbEntryStored]
    let fpus: [CarbEntryStored]

    let units: GlucoseUnits
    let bolusDisplayThreshold: BolusDisplayThreshold
    /// Baseline the FPU dots sit on, in display units — the bottom of the plotted range.
    let fpuBaseline: Decimal

    /// Time-to-x mapping for this frame, handed down by `ChartOverlayLayer` — already
    /// interpolated, and already carrying the live-pinch stretch.
    let viewport: ChartViewport

    /// Value-to-pixel mapping for the glucose pane, passed in so the markers and the selection
    /// overlay can never disagree about where a reading sits.
    let yPosition: (Decimal) -> CGFloat

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            for marker in markers {
                context.fill(marker.path, with: .color(marker.color))
                if let label = marker.label {
                    context.draw(label, at: marker.labelPoint, anchor: marker.labelAnchor)
                }
            }
        }
    }

    // MARK: - Marker geometry

    private struct Marker {
        let path: Path
        let color: Color
        let label: Text?
        let labelPoint: CGPoint
        let labelAnchor: UnitPoint
    }

    /// Gap between a marker's bounding box and its label.
    private static let labelSpacing: CGFloat = 2

    /// Reach past each edge, in points, so a marker whose centre has just left the screen still
    /// draws the pixels that are still inside. Half the widest treatment symbol.
    private static let cullMarginPoints: CGFloat = MainChartHelper.Config.maxCarbSize

    private var cullRange: ClosedRange<Date> {
        viewport.cullRange(marginPoints: Self.cullMarginPoints)
    }

    private var markers: [Marker] {
        var markers: [Marker] = []
        appendBoluses(to: &markers)
        appendCarbs(to: &markers)
        appendFPUs(to: &markers)
        return markers
    }

    /// The box a marker of `size` occupies, centred on its data point.
    private func box(at date: Date, y: CGFloat, size: CGFloat) -> CGRect {
        CGRect(x: viewport.x(for: date) - size / 2, y: y - size / 2, width: size, height: size)
    }

    private func appendBoluses(to markers: inout [Marker]) {
        let range = cullRange
        // Resolved with the same builder the chart used, so the two renderings cannot disagree
        // about a marker's anchor, size or label.
        let marks = MainChartHelper.bolusMarks(
            MainChartHelper.windowSlice(
                insulin, from: range.lowerBound, through: range.upperBound,
                ascending: true, date: { $0.timestamp }
            ),
            anchors: anchors,
            units: units,
            threshold: bolusDisplayThreshold
        )
        for mark in marks {
            let rect = box(at: mark.date, y: yPosition(mark.yPosition), size: mark.size)
            markers.append(Marker(
                path: TreatmentTriangleSymbol(pointsDown: true).path(in: rect),
                color: .insulin,
                label: mark.label.map { Text($0).font(.caption2).foregroundStyle(Color.primary) },
                labelPoint: CGPoint(x: rect.midX, y: rect.minY - Self.labelSpacing),
                labelAnchor: .bottom
            ))
        }
    }

    private func appendCarbs(to markers: inout [Marker]) {
        let range = cullRange
        // Carbs (and FPUs below) are fetched newest-first; the slice keeps that order, which
        // only decides which of two overlapping markers is drawn on top.
        let marks = MainChartHelper.carbMarks(
            MainChartHelper.windowSlice(
                carbs, from: range.lowerBound, through: range.upperBound,
                ascending: false, date: { $0.date }
            ),
            anchors: anchors,
            units: units
        )
        for mark in marks {
            let rect = box(at: mark.date, y: yPosition(mark.yPosition), size: mark.size)
            markers.append(Marker(
                // The bolus triangle mirrored: carbs point up at the curve from below.
                path: TreatmentTriangleSymbol(pointsDown: false).path(in: rect),
                color: .orange,
                label: mark.label.map { Text($0).font(.caption2).foregroundStyle(Color.primary) },
                labelPoint: CGPoint(x: rect.midX, y: rect.maxY + Self.labelSpacing),
                labelAnchor: .top
            ))
        }
    }

    /// FPUs sit on the baseline rather than on the curve, and carry no label.
    ///
    /// They kept Swift Charts' default circle symbol, whose `symbolSize` is an *area* in square
    /// points — not the bounding box the treatment triangles use — so the diameter is recovered
    /// from it rather than used directly.
    private func appendFPUs(to markers: inout [Marker]) {
        let range = cullRange
        let marks = MainChartHelper.fpuMarks(
            MainChartHelper.windowSlice(
                fpus, from: range.lowerBound, through: range.upperBound,
                ascending: false, date: { $0.date }
            ),
            baseline: fpuBaseline
        )
        let y = yPosition(fpuBaseline)
        for mark in marks {
            let diameter = 2 * sqrt(max(mark.area, 0) / .pi)
            let rect = CGRect(
                x: viewport.x(for: mark.date) - diameter / 2,
                y: y - diameter / 2,
                width: diameter,
                height: diameter
            )
            markers.append(Marker(
                path: Path(ellipseIn: rect),
                color: .brown,
                label: nil,
                labelPoint: .zero,
                labelAnchor: .center
            ))
        }
    }
}
