import Charts
import CoreData
import Foundation
import SwiftUI

/// Shared triangle for the treatment markers: boluses point down at the glucose curve from
/// above, carb entries point up at it from below. A `ChartSymbolShape` is rasterized as a
/// path, unlike `.symbol { Image(...) }`, which instantiates a SwiftUI view per data point —
/// the dominant cost of these series when SMBs land every few minutes.
struct TreatmentTriangleSymbol: ChartSymbolShape {
    let pointsDown: Bool

    /// Corner radius as a fraction of the symbol's smaller dimension. Small enough that the
    /// apex still reads as a point at the sizes these markers are drawn at.
    private var cornerFraction: CGFloat { 0.11 }

    func path(in rect: CGRect) -> Path {
        let corners: [CGPoint] = pointsDown
            ? [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.midX, y: rect.maxY)
            ]
            : [
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.midX, y: rect.minY)
            ]

        let radius = min(rect.width, rect.height) * cornerFraction
        var path = Path()
        // Begin midway along the closing edge so the first arc has a straight run-up into
        // the first corner, the same as every other corner gets.
        let last = corners[corners.count - 1]
        path.move(to: CGPoint(x: (last.x + corners[0].x) / 2, y: (last.y + corners[0].y) / 2))
        for index in corners.indices {
            path.addArc(
                tangent1End: corners[index],
                tangent2End: corners[(index + 1) % corners.count],
                radius: radius
            )
        }
        path.closeSubpath()
        return path
    }

    var perceptualUnitRect: CGRect { CGRect(x: 0, y: 0, width: 1, height: 1) }
}

enum MainChartHelper {
    /// The slice of a date-sorted series covering `start ... end`, located by binary search.
    ///
    /// A linear `filter` was cheap while the series were culled once per render-window
    /// re-anchor — a handful of times per session. Culling to the visible window re-runs the
    /// cull on every pan step instead, and each pass touches a Core Data date on every one of
    /// up to 72 h of entries, so the scan and not the marks would become the cost.
    ///
    /// Both sort directions are supported because the chart's series come from fetched-results
    /// controllers with opposite sort descriptors: glucose and pump events ascend, carbs and
    /// FPUs descend. Entries without a date are ordered outside the window and dropped, exactly
    /// as the `filter` this replaces dropped them.
    static func windowSlice<T>(
        _ items: [T],
        from start: Date,
        through end: Date,
        ascending: Bool,
        date: (T) -> Date?
    ) -> [T] {
        guard !items.isEmpty, start <= end else { return [] }

        let lower: Int
        let upper: Int
        if ascending {
            lower = partitionPoint(items) { (date($0) ?? .distantPast) >= start }
            upper = partitionPoint(items) { (date($0) ?? .distantPast) > end }
        } else {
            lower = partitionPoint(items) { (date($0) ?? .distantFuture) <= end }
            upper = partitionPoint(items) { (date($0) ?? .distantFuture) < start }
        }

        guard lower < upper else { return [] }
        return items[lower ..< upper].filter { date($0) != nil }
    }

    /// The first index at which `isSatisfied` becomes true, for a predicate that is false over
    /// a prefix and true over the rest — `items.count` when it never does.
    private static func partitionPoint<T>(_ items: [T], _ isSatisfied: (T) -> Bool) -> Int {
        var low = 0
        var high = items.count
        while low < high {
            let mid = low + (high - low) / 2
            if isSatisfied(items[mid]) {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return low
    }

    // MARK: - Resolved treatment marks

    /// One glucose reading, resolved once for both drawing and anchoring.
    ///
    /// The treatment markers hang off the curve, so every one of them searches this series,
    /// and `GlucoseChartView` walks it on every pan, pinch and scrub frame. Over
    /// `GlucoseStored` either meant a Core Data property access per comparison — ten or so
    /// per marker — plus a colour resolved per reading per layout. Read out into values
    /// first, the search is contiguous `Double` and `Decimal` work and the draw loop touches
    /// no Core Data at all.
    struct GlucoseDot {
        /// Epoch seconds, kept alongside `date` so the anchor search compares `Double`s.
        let time: TimeInterval
        let date: Date
        /// Already in display units.
        let value: Decimal
        /// Smoothed value, in display units. `nil` when the reading carries none.
        let smoothed: Decimal?
        let isManual: Bool
        let color: Color
    }

    /// A bolus resolved to everything needed to draw it, so that `TreatmentOverlay`'s draw loop
    /// does no Core Data work beyond reading the events themselves. `label` is `nil` when the
    /// dose is below the display threshold, so a hidden number costs no text to lay out.
    struct BolusMark: Identifiable {
        let id: String
        let date: Date
        let yPosition: Decimal
        /// Side of the marker's bounding box, in points. Was an SF Symbol point size; as a box
        /// it keeps the same amount-driven growth the `Image` had.
        let size: CGFloat
        let label: String?
    }

    /// The same for a carb entry, which carries its gram label at every threshold setting.
    struct CarbMark: Identifiable {
        let id: String
        let date: Date
        let yPosition: Decimal
        let size: CGFloat
        let label: String?
    }

    /// An FPU dot. These sit on the baseline rather than on the curve and carry no label, and
    /// they keep Swift Charts' default circle symbol — whose `symbolSize` is an *area* in
    /// square points, not the bounding box the triangles use.
    struct FPUMark: Identifiable {
        let id: String
        let date: Date
        let yPosition: Decimal
        let area: CGFloat
    }

    /// Reads the glucose series out of Core Data into dots, once per data change.
    ///
    /// The colour is resolved here rather than per draw: `getDynamicGlucoseColor` used to run
    /// once per reading per layout, inside `GlucoseChartView`'s mark body.
    static func glucoseDots(
        _ readings: [GlucoseStored],
        units: GlucoseUnits,
        highGlucose: Decimal,
        lowGlucose: Decimal,
        currentGlucoseTarget: Decimal,
        glucoseColorScheme: GlucoseColorScheme
    ) -> [GlucoseDot] {
        let isMgdL = units == .mgdL
        // TODO: workaround for now: set low value to 55, to have dynamic color shades between 55 and user-set low (approx. 70); same for high glucose
        let hardCodedLow = Decimal(55)
        let hardCodedHigh = Decimal(220)
        let isDynamicColorScheme = glucoseColorScheme == .dynamicColor
        let highColorValue = isDynamicColorScheme ? hardCodedHigh : highGlucose
        let lowColorValue = isDynamicColorScheme ? hardCodedLow : lowGlucose

        var dots: [GlucoseDot] = []
        dots.reserveCapacity(readings.count)
        for reading in readings {
            guard let date = reading.date else { continue }
            let mgdl = Decimal(reading.glucose)
            let smoothed = reading.smoothedGlucose.flatMap { value -> Decimal? in
                let decimal = value.decimalValue
                guard decimal != 0 else { return nil }
                return isMgdL ? decimal : decimal.asMmolL
            }
            dots.append(GlucoseDot(
                time: date.timeIntervalSince1970,
                date: date,
                value: isMgdL ? mgdl : mgdl.asMmolL,
                smoothed: smoothed,
                isManual: reading.isManual,
                color: Trio.getDynamicGlucoseColor(
                    glucoseValue: mgdl,
                    highGlucoseColorValue: highColorValue,
                    lowGlucoseColorValue: lowColorValue,
                    targetGlucose: currentGlucoseTarget,
                    glucoseColorScheme: glucoseColorScheme
                )
            ))
        }
        return dots
    }

    /// The anchor nearest `time`: locate the first entry at or after it, then take the closer
    /// of the two straddling it.
    ///
    /// Written this way on purpose. The version this replaces tracked a best candidate inside
    /// the binary descent and compared it with
    /// `abs(midTime - time) < abs(closest.date?.timeIntervalSince1970 ?? 0 - time)` — where
    /// `-` binds tighter than `??`, so the right-hand side was the candidate's raw epoch
    /// seconds (~1.8e9) rather than its distance. Every real distance beat that, so the
    /// candidate was overwritten on every iteration and the answer was whichever entry the
    /// descent visited last — one of the two neighbours, but which one depended on the array's
    /// length. The series are re-sliced as the chart is panned, so the same bolus resolved to
    /// a different reading from one pan step to the next and its marker hopped a full CGM
    /// interval. Taking the insertion point makes the answer a function of `time` alone.
    static func nearestDot(_ dots: [GlucoseDot], time: TimeInterval) -> GlucoseDot? {
        guard !dots.isEmpty else { return nil }

        var low = 0
        var high = dots.count
        while low < high {
            let mid = low + (high - low) / 2
            if dots[mid].time < time {
                low = mid + 1
            } else {
                high = mid
            }
        }

        let before = low > 0 ? dots[low - 1] : nil
        let after = low < dots.count ? dots[low] : nil

        switch (before, after) {
        case let (before?, after?):
            return abs(after.time - time) < abs(before.time - time) ? after : before
        case let (before?, nil):
            return before
        case let (nil, after?):
            return after
        case (nil, nil):
            return nil
        }
    }

    /// Resolves the windowed bolus events into marks. Input order is preserved, so the caller's
    /// `ascending` stays true of the result and the draw order is unchanged.
    static func bolusMarks(
        _ events: [PumpEventStored],
        dots: [GlucoseDot],
        units: GlucoseUnits,
        threshold: BolusDisplayThreshold
    ) -> [BolusMark] {
        let offset = bolusOffset(units: units)
        var marks: [BolusMark] = []
        marks.reserveCapacity(events.count)
        for event in events {
            guard let date = event.timestamp else { continue }
            let amount = event.bolus?.amount ?? 0 as NSDecimalNumber
            guard amount != 0, let dot = nearestDot(dots, time: date.timeIntervalSince1970) else { continue }

            let decimalAmount = amount as Decimal
            marks.append(BolusMark(
                id: event.id ?? "bolus-\(date.timeIntervalSince1970)",
                date: date,
                yPosition: dot.value + offset,
                size: Config.bolusSize + CGFloat(truncating: amount) * Config.bolusScale,
                // The threshold hides the number, never the triangle — see the setting's own
                // hint. Deciding it here means a dose below it costs no companion mark at all,
                // where the test used to sit inside an annotation that then drew nothing.
                label: decimalAmount >= threshold.rawValue
                    ? Formatter.bolusFormatter.string(from: amount)
                    : nil
            ))
        }
        return marks
    }

    /// The same for carb entries. These arrive newest-first from their fetched-results
    /// controller; that order is preserved here too.
    static func carbMarks(
        _ entries: [CarbEntryStored],
        dots: [GlucoseDot],
        units: GlucoseUnits
    ) -> [CarbMark] {
        let offset = bolusOffset(units: units)
        var marks: [CarbMark] = []
        marks.reserveCapacity(entries.count)
        for entry in entries {
            guard let date = entry.date,
                  let dot = nearestDot(dots, time: date.timeIntervalSince1970) else { continue }

            let carbs = entry.carbs
            marks.append(CarbMark(
                id: entry.id?.uuidString ?? "carb-\(date.timeIntervalSince1970)",
                date: date,
                yPosition: dot.value - offset,
                size: min(Config.carbsSize + CGFloat(carbs) * Config.carbsScale, Config.maxCarbSize),
                label: Formatter.integerFormatter.string(from: carbs as NSNumber)
            ))
        }
        return marks
    }

    /// The same for FPUs, which need no anchor: they sit on `baseline`, already in display
    /// units.
    static func fpuMarks(_ entries: [CarbEntryStored], baseline: Decimal) -> [FPUMark] {
        var marks: [FPUMark] = []
        marks.reserveCapacity(entries.count)
        for entry in entries {
            guard let date = entry.date else { continue }
            let carbs = entry.carbs
            marks.append(FPUMark(
                id: entry.id?.uuidString ?? "fpu-\(date.timeIntervalSince1970)",
                date: date,
                yPosition: baseline,
                area: (Config.fpuSize + CGFloat(carbs) * Config.carbsScale) * 1.8
            ))
        }
        return marks
    }

    enum Config {
        /// How far back the chart's `startMarker` is anchored — the fixed 24 h
        /// history window loaded on every open. Independent of the currently
        /// visible viewport, which the user can pinch-zoom within this range.
        static let chartHistorySeconds: TimeInterval = 72 * 3600
        /// Backfill triggers when the visible leading edge gets this close
        /// Visible x-axis window seeded on first launch of the chart (matches the old 6 h default).
        static let defaultVisibleSeconds: TimeInterval = 6 * 3600
        /// Tightest pinch-in zoom.
        static let minVisibleSeconds: TimeInterval = 1 * 3600
        /// Widest pinch-out zoom.
        static let maxVisibleSeconds: TimeInterval = 24 * 3600
        /// Double-tap cycles the visible window through these presets.
        static let zoomPresets: [TimeInterval] = [6 * 3600, 12 * 3600, 24 * 3600]
        /// When auto-follow re-anchors to `now` at tight zoom, the current reading sits this
        /// fraction from the trailing edge (0.55 makes the crossover land at ~6 h, so the
        /// forecast-anchored framing at 6 h and wider is unchanged; below it, `now` stays on-screen).
        static let followForecastPeekFraction: CGFloat = 0.55
        /// Render window extends this many visible-windows beyond each visible edge.
        static let renderWindowPadFactor = 1.5
        /// The glucose readings and the bolus / carb / FPU markers are laid out only for
        /// the visible window plus this fraction of it at each edge, rather than for the
        /// whole render window. They are the densest marks on the chart — ~900 readings
        /// alone at the widest zoom over 72 h of history — and the render window is four
        /// visible windows wide, so three quarters of that layout work was being spent on
        /// marks the user cannot see. The pad is what a mark straddling an edge, and the
        /// smoothed curve running off one, need in order to still enter the viewport.
        ///
        /// It doubles as the pan tolerance: the window is re-anchored once the visible
        /// window reaches the end of the pad, so panning re-lays the marks roughly every
        /// 5 % of a viewport — each re-layout now being a fraction of the old one.
        static let treatmentRenderPadFactor = 0.05
        /// Re-anchor when the visible edge gets within this fraction of a
        /// visible-window of the render window's edge.
        static let renderWindowMarginFactor = 0.5
        /// Geometric grid for pinch commits (~4 % per step). Every committed zoom step
        /// re-lays the full-width canvas, so this bounds a halving of the visible window
        /// to roughly 18 re-layouts instead of hundreds.
        static let zoomStepRatio: Double = 1.04
        /// Live pinch previews as a transform; once the stretch drifts past
        /// this ratio a crisp re-layout is committed mid-gesture, so the
        /// distortion stays bounded.
        static let pinchCommitScaleDrift: Double = 1.25
        /// How far (pt) a one-finger touch may travel and still count as a stationary
        /// press-to-inspect; beyond this the touch becomes a pan.
        static let inspectMovementTolerance: CGFloat = 10
        /// Width (pt) of the strips at the viewport edges where a scrubbing finger makes
        /// the chart auto-pan to reveal more data; pan speed scales with edge depth.
        static let edgePanZoneWidth: CGFloat = 44
        /// How long (s) a one-finger touch must rest before the inspect popover appears.
        /// Without this, every drag briefly triggered inspect on touch-down — and each
        /// selection change re-lays the canvas, stalling the pan as it starts.
        static let inspectHoldDelay: TimeInterval = 0.15
        static let bolusSize: CGFloat = 5
        static let bolusScale: CGFloat = 1.8
        static let carbsSize: CGFloat = 5
        static let maxCarbSize: CGFloat = 30
        static let carbsScale: CGFloat = 0.3
        static let fpuSize: CGFloat = 10
        static let maxGlucose = 270
        static let minGlucose = 45
    }

    /// Visual scaling applied to IOB values on the shared COB/IOB axis (COB is usually
    /// much larger than IOB). Single source of truth for the chart marks, the y-domain,
    /// and the shell's selection overlay.
    static func scaledIobAmount<T: Numeric & Comparable>(_ rawAmount: T) -> T
        where T: ExpressibleByIntegerLiteral
    {
        rawAmount > 0 ? rawAmount * 8 : rawAmount * 9
    }

    /// The combined y-domain of the COB/IOB chart. Used by both the canvas chart and the
    /// shell's selection overlay, which must agree exactly on the value-to-pixel mapping.
    static func cobIobYDomain(
        minCob: Decimal,
        maxCob: Decimal,
        minIob: Decimal,
        maxIob: Decimal
    ) -> ClosedRange<Double> {
        let iobMin = scaledIobAmount(minIob)
        let iobMax = scaledIobAmount(maxIob)
        let minValue = min(minCob, iobMin)
        let maxValue = max(maxCob, iobMax)
        return Double(minValue) ... Double(maxValue)
    }

    static func bolusOffset(units: GlucoseUnits) -> Decimal {
        units == .mgdL ? 20 : (20 / 18)
    }

    static func calculateDuration(
        objectID: NSManagedObjectID,
        attribute: String,
        context: NSManagedObjectContext
    ) -> TimeInterval? {
        do {
            let object = try context.existingObject(with: objectID)
            if let attributeValue = object.value(forKey: attribute) as? NSDecimalNumber {
                let doubleValue = attributeValue.doubleValue
                if doubleValue != 0 {
                    return TimeInterval(doubleValue * 60) // return seconds
                }
            } else {
                debugPrint("Attribute \(attribute) not found or not of type NSDecimalNumber")
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to calculate duration for object with error: \(error)"
            )
        }

        return nil
    }

    static func calculateTarget(objectID: NSManagedObjectID, attribute: String, context: NSManagedObjectContext) -> Decimal? {
        do {
            let object = try context.existingObject(with: objectID)
            if let attributeValue = object.value(forKey: attribute) as? NSDecimalNumber, attributeValue != 0 {
                return attributeValue.decimalValue
            }
        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to calculate target for object with error: \(error)"
            )
        }
        return nil
    }
}

// MARK: - Rule Marks and Charts configurations

extension MainChartCanvas {
    func drawCurrentTimeMarker() -> some ChartContent {
        RuleMark(
            x: .value(
                "",
                Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970)),
                unit: .second
            )
        ).lineStyle(.init(lineWidth: 2, dash: [3])).foregroundStyle(Color(.systemGray2))
    }

    /// High and low threshold lines. Horizontal rules span the whole x-domain, so they stay
    /// visually static while the chart scrolls. (Moved here from the deleted static-axis
    /// overlay chart.)
    @ChartContentBuilder func drawThresholdLines() -> some ChartContent {
        if thresholdLines {
            // TODO: workaround for now: set low value to 55, to have dynamic color shades between 55 and user-set low (approx. 70); same for high glucose
            let hardCodedLow = Decimal(55)
            let hardCodedHigh = Decimal(220)
            let isDynamicColorScheme = glucoseColorScheme == .dynamicColor

            let highColor = Trio.getDynamicGlucoseColor(
                glucoseValue: highGlucose,
                highGlucoseColorValue: isDynamicColorScheme ? hardCodedHigh : highGlucose,
                lowGlucoseColorValue: isDynamicColorScheme ? hardCodedLow : lowGlucose,
                targetGlucose: currentGlucoseTarget,
                glucoseColorScheme: glucoseColorScheme
            )
            let lowColor = Trio.getDynamicGlucoseColor(
                glucoseValue: lowGlucose,
                highGlucoseColorValue: isDynamicColorScheme ? hardCodedHigh : highGlucose,
                lowGlucoseColorValue: isDynamicColorScheme ? hardCodedLow : lowGlucose,
                targetGlucose: currentGlucoseTarget,
                glucoseColorScheme: glucoseColorScheme
            )

            RuleMark(y: .value("High", units == .mgdL ? highGlucose : highGlucose.asMmolL))
                .foregroundStyle(highColor)
                .lineStyle(.init(lineWidth: 1, dash: [5]))
            RuleMark(y: .value("Low", units == .mgdL ? lowGlucose : lowGlucose.asMmolL))
                .foregroundStyle(lowColor)
                .lineStyle(.init(lineWidth: 1, dash: [5]))
        }
    }

    /// X-axis grid/label stride for the current continuous zoom level. Same ladder as the
    /// old presets: up to 6 h visible -> 1 h, up to 12 h -> 2 h, wider -> 4 h.
    var xAxisStrideHours: Int {
        let visibleHours = visibleSeconds / 3600
        if visibleHours <= 6 { return 1 }
        if visibleHours <= 12 { return 2 }
        return 4
    }

    /// Calendar-hour axis mark dates for the given range, anchored to absolute time
    /// (multiples of `xAxisStrideHours` counted from midnight, DST-safe via `Calendar`),
    /// unlike `.stride(by: .hour, count:)`, which anchors its sequence to the domain start.
    func hourAxisMarks(over range: ClosedRange<Date>) -> [Date] {
        let strideHours = xAxisStrideHours
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: range.lowerBound)
        let hour = components.hour ?? 0
        components.hour = hour - hour % strideHours
        guard var mark = calendar.date(from: components) else { return [] }

        var marks: [Date] = []
        while mark <= range.upperBound {
            if mark >= range.lowerBound {
                marks.append(mark)
            }
            guard let next = calendar.date(byAdding: .hour, value: strideHours, to: mark) else { break }
            mark = next
        }
        return marks
    }

    var mainChartXAxis: some AxisContent {
        AxisMarks(values: hourAxisMarks(over: windowStart ... windowEnd)) { _ in
            if displayXgridLines {
                AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
            } else {
                AxisGridLine(stroke: .init(lineWidth: 0, dash: [2, 3]))
            }
        }
    }

    /// Grid lines PLUS hour labels. Used only by the bottom (COB/IOB) pane so the time
    /// labels render exactly once for the whole stack; the basal and glucose panes use
    /// `mainChartXAxis` (grid lines only) at the same absolute-anchored mark dates.
    var basalChartXAxis: some AxisContent {
        AxisMarks(values: hourAxisMarks(over: windowStart ... windowEnd)) { value in
            if displayXgridLines {
                AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
            } else {
                AxisGridLine(stroke: .init(lineWidth: 0, dash: [2, 3]))
            }
            // Midnight ticks carry the day ("TUE 07") so panned-back history
            // stays unambiguous; all other ticks show the hour.
            if let date = value.as(Date.self), calendar.component(.hour, from: date) == 0 {
                AxisValueLabel(anchor: .top) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated).day(.twoDigits)).uppercased())
                        .font(.footnote).bold()
                        .foregroundStyle(Color.primary)
                }
            } else {
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)), anchor: .top)
                    .font(.footnote).foregroundStyle(Color.primary)
            }
        }
    }

    var cobIobChartYAxis: some AxisContent {
        // Only two y-grid lines — at the top and bottom of the pane — instead of
        // automatic marks: the values are exactly the bounds of the same combined
        // COB/IOB domain the chart is scaled to.
        let domain = combinedYDomain()
        return AxisMarks(position: .trailing, values: [domain.lowerBound, domain.upperBound]) { _ in
            if displayYgridLines {
                AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
            } else {
                AxisGridLine(stroke: .init(lineWidth: 0, dash: [2, 3]))
            }
        }
    }
}
