import Foundation
import SwiftUI

/// Selection marker/readout color for a glucose value, shared with the shell's overlay dot.
func selectionMarkColor(
    for glucose: GlucoseStored,
    highGlucose: Decimal,
    lowGlucose: Decimal,
    currentGlucoseTarget: Decimal,
    glucoseColorScheme: GlucoseColorScheme
) -> Color {
    let hardCodedLow = Decimal(55)
    let hardCodedHigh = Decimal(220)
    let isDynamicColorScheme = glucoseColorScheme == .dynamicColor

    return Trio.getDynamicGlucoseColor(
        glucoseValue: Decimal(glucose.glucose),
        highGlucoseColorValue: isDynamicColorScheme ? hardCodedHigh : highGlucose,
        lowGlucoseColorValue: isDynamicColorScheme ? hardCodedLow : lowGlucose,
        targetGlucose: currentGlucoseTarget,
        glucoseColorScheme: glucoseColorScheme
    )
}

/// Resolves a scrub timestamp to the records it points at, so the chart's marks and the
/// Home meal slot's readout always describe the same reading.
enum ChartSelectionLookup {
    /// Half-width of the lookup window. Pairs with the 300 s scrub snap in
    /// `MainChartView.updateSelection`, so a snapped selection lands on exactly one reading.
    static let window: TimeInterval = 150

    /// How long the readout survives a scrub that resolves to nothing: long enough to bridge
    /// a missing reading, short enough not to feel stuck once the finger lifts.
    static let decay: TimeInterval = 0.6

    /// The fade the readout swaps in and out with. Quick, because it answers the finger:
    /// anything slower reads as lag between the touch and the values it asked for.
    ///
    /// Applied to the meal slot itself, keyed on whether a readout is showing: scoping it
    /// there keeps the transaction off everything else that changes in the same frame, which
    /// a `withAnimation` at the mutation site could not do.
    static let readoutFade: Animation = .easeOut(duration: 0.12)

    /// How far a held determination may sit from the selection before it is dropped instead:
    /// two cadences, so a hole is bridged but a jump elsewhere on the chart is not.
    static let determinationHold: TimeInterval = 600

    static func glucose(at date: Date, in readings: [GlucoseStored]) -> GlucoseStored? {
        let range = date.addingTimeInterval(-window) ... date.addingTimeInterval(window)
        return readings.first { $0.date.map(range.contains) ?? false }
    }

    static func determination(at date: Date, in determinations: [OrefDetermination]) -> OrefDetermination? {
        let range = date.addingTimeInterval(-window) ... date.addingTimeInterval(window)
        let now = Date.now
        return determinations.first {
            $0.deliverAt ?? now >= range.lowerBound && $0.deliverAt ?? now <= range.upperBound
        }
    }
}

/// The selection readout, shown in the Home meal slot in place of IOB / COB / alarms while a
/// scrub is live. A card floating over the glucose pane covered the very data it described;
/// the meal slot is always on screen and its live values are superseded anyway, so taking it
/// over reflows nothing.
struct ChartSelectionRow: View {
    let selectedGlucose: GlucoseStored
    /// COB and IOB both come from the one determination nearest the selection.
    let determination: OrefDetermination?
    let units: GlucoseUnits
    let highGlucose: Decimal
    let lowGlucose: Decimal
    let currentGlucoseTarget: Decimal
    let glucoseColorScheme: GlucoseColorScheme
    let isSmoothingEnabled: Bool

    private var glucoseToDisplay: Decimal {
        units == .mgdL ? Decimal(selectedGlucose.glucose) : Decimal(selectedGlucose.glucose).asMmolL
    }

    /// mmol/L is written to one decimal even when it is a whole number — 8 reads as 8.0, the
    /// way the rest of the app writes it — and both units go through a formatter so the
    /// decimal separator follows the locale rather than `Decimal.description`'s hard dot.
    private static let glucoseFormatter: (GlucoseUnits) -> NumberFormatter = { units in
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        formatter.minimumFractionDigits = units == .mgdL ? 0 : 1
        formatter.maximumFractionDigits = units == .mgdL ? 0 : 1
        return formatter
    }

    private func glucoseString(_ value: Decimal) -> String {
        Self.glucoseFormatter(units).string(from: value as NSDecimalNumber) ?? value.description
    }

    private var pointMarkColor: Color {
        selectionMarkColor(
            for: selectedGlucose,
            highGlucose: highGlucose,
            lowGlucose: lowGlucose,
            currentGlucoseTarget: currentGlucoseTarget,
            glucoseColorScheme: glucoseColorScheme
        )
    }

    private var timeString: String {
        selectedGlucose.date?.formatted(.dateTime.hour().minute(.twoDigits)) ?? ""
    }

    /// Stand-in for a value the selection resolves to nothing: the item keeps its place and
    /// says so rather than vanishing. The spaces are part of the string — the item takes a
    /// `Text` — and keep the dash off its own glyph and off the next item.
    private static let missingValue = Text(verbatim: " \u{2013} ").foregroundStyle(.secondary)

    var body: some View {
        // Nothing may truncate — SwiftUI ellipsised the glucose value — so the whole row
        // steps down a type size until it fits.
        ViewThatFits(in: .horizontal) {
            row(font: .callout)
            row(font: .subheadline)
            row(font: .footnote)
        }
        // Scrubbing changes these several times a second; animating them smears the digits.
        .animation(nil, value: selectedGlucose.date)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .glassPanel(tint: pointMarkColor, tintOpacity: 0.10, strokeOpacity: 0.25)
    }

    /// Fixed spacing rather than `Spacer`s, so the row hugs its content: with no determination
    /// it shrinks to time and glucose instead of stretching the slot around them. The items
    /// are the plain strings — wide enough apart that a value growing a digit can't run into
    /// its neighbour's glyph, and no reserved width behind them.
    @ViewBuilder private func row(font: Font) -> some View {
        HStack(spacing: 12) {
            item(icon: "clock", tint: .secondary, value: Text(timeString))

            glucoseGroup

            // Both stay in the row when the scrub lands where oref produced no determination
            // — a gap in the data, or a loop that never ran — and show a dash instead.
            let iobUnit = Text(String(localized: " U", comment: "Insulin unit")).fontWeight(.regular)
            let iobString = determination?.iob
                .flatMap { Formatter.decimalFormatterWithTwoFractionDigits.string(from: $0) }
            item(
                icon: "syringe.fill",
                tint: Color.insulin,
                value: iobString.map { Text($0) + iobUnit } ?? Self.missingValue
            )

            let cobUnit = Text(String(localized: " g", comment: "gram of carbs")).fontWeight(.regular)
            let cobString = determination
                .flatMap { Formatter.integerFormatter.string(from: $0.cob as NSNumber) }
            item(
                icon: "fork.knife",
                tint: .loopYellow,
                value: cobString.map { Text($0) + cobUnit } ?? Self.missingValue
            )
        }
        .font(font).fontWeight(.bold).fontDesign(.rounded)
        // equal-width digits, so a value can't wobble as its digits change mid-scrub
        .monospacedDigit()
        .lineLimit(1)
    }

    /// The reading under the drop and, with smoothing on, the smoothed value in brackets
    /// behind it — marked with the same sparkles glyph the History tab puts on a smoothed
    /// reading. Only the drop and the raw value take the glucose color, so the bracketed
    /// value can't be misread as a second state.
    @ViewBuilder private var glucoseGroup: some View {
        // verbatim: brackets have nothing to translate, and Xcode would otherwise extract
        // them into the string catalog
        let reading = Text(glucoseString(glucoseToDisplay)).foregroundStyle(pointMarkColor)
        let smoothed = smoothedToDisplay.map {
            (
                Text(verbatim: "(")
                    + Text(Image(systemName: "sparkles"))
                    + Text(verbatim: " ")
                    + Text(glucoseString($0))
                    + Text(verbatim: ")")
            ).foregroundStyle(.secondary)
        }

        item(
            icon: "drop.fill",
            tint: pointMarkColor,
            value: smoothed.map { reading + Text(verbatim: " ") + $0 } ?? reading
        )
    }

    /// The smoothed reading in display units, or nil with smoothing off or no smoothed value.
    private var smoothedToDisplay: Decimal? {
        guard isSmoothingEnabled, let smoothed = selectedGlucose.smoothedGlucose else { return nil }
        return units == .mgdL ? smoothed.decimalValue : smoothed.decimalValue.asMmolL
    }

    /// One value plus its glyph.
    @ViewBuilder private func item(icon: String? = nil, tint: Color = .secondary, value: Text) -> some View {
        HStack(spacing: 4) {
            if let icon {
                // scales with whichever step `ViewThatFits` settled on
                Image(systemName: icon)
                    .imageScale(.small)
                    .foregroundStyle(tint)
            }
            value
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
