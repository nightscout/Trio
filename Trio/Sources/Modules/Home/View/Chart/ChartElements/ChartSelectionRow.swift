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

    private var pointMarkColor: Color {
        selectionMarkColor(
            for: selectedGlucose,
            highGlucose: highGlucose,
            lowGlucose: lowGlucose,
            currentGlucoseTarget: currentGlucoseTarget,
            glucoseColorScheme: glucoseColorScheme
        )
    }

    /// A time wide enough to reserve room for any other the scrub can land on: two-digit hour
    /// plus, where the locale writes one, an AM/PM marker. Formatted rather than hard-coded so
    /// that holds in 12- and 24-hour locales alike.
    private static let timeTemplateDate = Calendar.current
        .date(from: DateComponents(year: 2000, month: 1, day: 1, hour: 22, minute: 38)) ?? .distantPast

    private var timeString: String {
        selectedGlucose.date?.formatted(.dateTime.hour().minute(.twoDigits)) ?? ""
    }

    private var timeTemplate: String {
        Self.timeTemplateDate.formatted(.dateTime.hour().minute(.twoDigits))
    }

    /// Stand-in for a value the selection resolves to nothing: the item keeps its place and
    /// its width, and says so rather than vanishing.
    private static let missingValue = Text(verbatim: "–").foregroundStyle(.secondary)

    /// Widest reading the unit can produce: three digits in mg/dL, `88.8` in mmol/L.
    private var glucoseTemplate: String { units == .mgdL ? "888" : "88.8" }

    var body: some View {
        // Nothing may truncate — SwiftUI ellipsised the glucose value — so every group is
        // `fixedSize` and the whole row steps down a type size until it fits.
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
    /// it shrinks to time and glucose instead of stretching the slot around them.
    @ViewBuilder private func row(font: Font) -> some View {
        HStack(spacing: 12) {
            item(
                icon: "clock",
                tint: .secondary,
                value: Text(timeString),
                template: Text(timeTemplate)
            )

            glucoseGroup

            // Both stay in the row when the scrub lands where oref produced no determination
            // — a gap in the data, or a loop that never ran — and show a dash instead. Letting
            // them come and go would resize the row under the finger, which is the one thing
            // the reserved boxes exist to prevent.
            let iobUnit = Text(String(localized: " U", comment: "Insulin unit")).fontWeight(.regular)
            let iobString = determination?.iob
                .flatMap { Formatter.decimalFormatterWithTwoFractionDigits.string(from: $0) }
            item(
                icon: "syringe.fill",
                tint: Color.insulin,
                value: iobString.map { Text($0) + iobUnit } ?? Self.missingValue,
                template: Text(verbatim: "88.88") + iobUnit,
                alignment: iobString == nil ? .center : .leading
            )

            let cobUnit = Text(String(localized: " g", comment: "gram of carbs")).fontWeight(.regular)
            let cobString = determination
                .flatMap { Formatter.integerFormatter.string(from: $0.cob as NSNumber) }
            item(
                icon: "fork.knife",
                tint: .loopYellow,
                value: cobString.map { Text($0) + cobUnit } ?? Self.missingValue,
                template: Text(verbatim: "888") + cobUnit,
                alignment: cobString == nil ? .center : .leading
            )
        }
        .font(font).fontWeight(.bold).fontDesign(.rounded)
        // equal-width digits, so a value can't wobble inside its reserved box mid-scrub
        .monospacedDigit()
        .lineLimit(1)
    }

    /// The reading under the drop and, with smoothing on, the smoothed value in brackets
    /// behind it. The brackets are the whole label — a glyph there would read as another item
    /// — and only the drop and the raw value take the glucose color, so the bracketed value
    /// can't be misread as a second state. Each gets its own reserved box with the slack
    /// pushed outwards, so the pair stays welded together at every reading width.
    @ViewBuilder private var glucoseGroup: some View {
        // verbatim: brackets have nothing to translate, and Xcode would otherwise extract
        // them into the string catalog
        let open = Text(verbatim: "(")
        let close = Text(verbatim: ")")
        let reading = Text(glucoseToDisplay.description).foregroundStyle(pointMarkColor)
        let smoothed = smoothedToDisplay.map { (open + Text($0.description) + close).foregroundStyle(.secondary) }

        item(
            icon: "drop.fill",
            tint: pointMarkColor,
            value: smoothed.map { reading + $0 } ?? reading,
            // One box for the pair, not one each: separate boxes would park the reading's
            // spare digits between it and its bracket. The setting decides the width, not
            // the individual reading — with smoothing on the bracket's room is held even for
            // a reading that has no smoothed value, so the row never reflows mid-scrub; with
            // it off the box is just the reading and the row is that much tighter.
            template: isSmoothingEnabled
                ? Text(glucoseTemplate) + open + Text(glucoseTemplate) + close
                : Text(glucoseTemplate)
        )
    }

    /// The smoothed reading in display units, or nil with smoothing off or no smoothed value.
    private var smoothedToDisplay: Decimal? {
        guard isSmoothingEnabled, let smoothed = selectedGlucose.smoothedGlucose else { return nil }
        return units == .mgdL ? smoothed.decimalValue : smoothed.decimalValue.asMmolL
    }

    /// One value plus its glyph, laid out in the width `template` needs, so a reading that
    /// gains a digit mid-scrub can't resize its group and shove the row sideways. The template
    /// is hidden (hidden views are skipped by VoiceOver, which reads only the value) with the
    /// value drawn over it, and is a `Text` so a unit is measured inside the box at its own
    /// weight.
    ///
    /// Values are leading-aligned, so each starts at a fixed offset from its glyph and the
    /// slack a short number leaves collects at the end of its own box. Aligning from the right
    /// would move the number itself as digits come and go — 9 → 10, 99 → 100 — which is the
    /// wobble the reserved boxes exist to prevent.
    ///
    /// A missing-value dash passes `.center` instead: it stands for the whole box rather than
    /// starting one, so it belongs in the middle of the room it holds.
    @ViewBuilder private func item(
        icon: String? = nil,
        tint: Color = .secondary,
        value: Text,
        template: Text,
        alignment: Alignment = .leading
    ) -> some View {
        HStack(spacing: 4) {
            if let icon {
                // scales with whichever step `ViewThatFits` settled on
                Image(systemName: icon)
                    .imageScale(.small)
                    .foregroundStyle(tint)
            }
            template
                .hidden()
                .overlay(alignment: alignment) {
                    value.fixedSize(horizontal: true, vertical: false)
                }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
