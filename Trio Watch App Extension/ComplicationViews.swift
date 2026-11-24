import SwiftUI

enum ComplicationKind: String, CaseIterable, Identifiable {
    case glucose
    case gauge
    case iob
    case chart
    case loop

    var id: String { rawValue }

    var widgetKind: String {
        switch self {
        case .glucose: return "TrioGlucoseComplication"
        case .gauge: return "TrioGaugeComplication"
        case .iob: return "TrioIobComplication"
        case .chart: return "TrioChartComplication"
        case .loop: return "TrioLoopComplication"
        }
    }

    var displayName: String {
        switch self {
        case .glucose: return String(localized: "Trio Glucose", comment: "Name of the glucose watch complication")
        case .gauge: return String(localized: "Trio Gauge", comment: "Name of the glucose ring watch complication")
        case .iob: return String(localized: "Trio IOB", comment: "Name of the insulin on board watch complication")
        case .chart: return String(localized: "Trio Chart", comment: "Name of the glucose chart watch complication")
        case .loop: return String(localized: "Trio Loop", comment: "Name of the loop status watch complication")
        }
    }

    var summary: String {
        switch self {
        case .glucose:
            return String(
                localized: "Glucose and trend. Small Line sits under the glucose on circular slots, Corner Label on corners.",
                comment: "Description of the glucose watch complication"
            )
        case .gauge:
            return String(
                localized: "Glucose inside a ring that fills from low to high. Rectangular slots add Small Line, IOB and COB.",
                comment: "Description of the glucose ring watch complication"
            )
        case .iob:
            return String(
                localized: "Insulin on board first, with COB and glucose alongside. Fixed layout; only Mark Stale After applies.",
                comment: "Description of the insulin on board watch complication"
            )
        case .chart:
            return String(
                localized: "Glucose, the Small Line and IOB next to the last three hours of readings. Rectangular slots only.",
                comment: "Description of the glucose chart watch complication"
            )
        case .loop:
            return String(
                localized: "Shows if Trio is looping. Green: looped in the last 5 minutes. Yellow: up to 10 minutes ago. Red: longer ago. Below is the time of the last loop.",
                comment: "Description of the loop status watch complication"
            )
        }
    }

    var slots: [ComplicationSlot] {
        switch self {
        case .chart: return [.rectangular]
        case .gauge: return [.corner, .circular, .rectangular]
        case .glucose,
             .iob,
             .loop: return [.corner, .circular, .rectangular, .inline]
        }
    }
}

enum ComplicationSlot {
    case corner
    case circular
    case rectangular
    case inline
}

struct ComplicationRendering {
    var referenceDate: Date
    var isPlaceholder = false
    var fullColor = true
}

struct ComplicationModel {
    static let neutralRing = Gradient(colors: [.white, .white])
    static let staleText = Color(white: 0.65)
    static let loopGreen = Color(complicationHex: "#6FCF97") ?? .green
    static let loopYellow = Color(complicationHex: "#FFC145") ?? .yellow
    static let loopRed = Color(complicationHex: "#EB5757") ?? .red

    let kind: ComplicationKind
    let displayedState: ComplicationState
    let isStale: Bool
    let isLoopStale: Bool
    let isLoopUnknown: Bool
    let isPlaceholder: Bool
    let referenceDate: Date
    let fullColor: Bool

    init(kind: ComplicationKind, state: ComplicationState, rendering: ComplicationRendering) {
        self.kind = kind
        referenceDate = rendering.referenceDate
        isPlaceholder = rendering.isPlaceholder
        fullColor = rendering.fullColor
        isStale = !isPlaceholder && state.isStale(at: referenceDate)
        isLoopStale = !isPlaceholder && state.isLoopStale(at: referenceDate)
        isLoopUnknown = !isPlaceholder && state.loopDate == nil
        var shown = state
        shown.lastLoopTime = state.loopAgeText(at: referenceDate)
        if isLoopStale {
            shown.iob = ComplicationState.missingValue
            shown.cob = ComplicationState.missingValue
        }
        displayedState = shown
    }

    var glucoseColor: Color {
        if isStale { return Self.staleText }
        return fullColor ? displayedState.glucoseColor : .primary
    }

    var glucoseTextColor: Color {
        if isStale { return Self.staleText }
        return fullColor && !displayedState.isMonochrome ? displayedState.glucoseColor : .primary
    }

    var valueColor: Color { isStale || isLoopStale || isLoopUnknown ? Self.staleText : .primary }

    var loopLineColor: Color { isLoopStale || isLoopUnknown ? Self.staleText : .primary }

    var statusLine: String {
        if isStale { return ageText }
        if isLoopStale { return "loop \(displayedState.lastLoopTime)" }
        return "COB \(displayedState.cob)"
    }

    var dimColor: Color { isStale ? Self.staleText : .primary }

    var trendArrow: String { isStale ? "" : displayedState.trendArrow }

    var glucoseText: String {
        isStale ? ComplicationState.missingValue : displayedState.glucose
    }

    var glucoseWithArrow: String {
        trendArrow.isEmpty ? glucoseText : "\(glucoseText)\(trendArrow)"
    }

    var glucoseWithArrowText: Text {
        Text(glucoseText).foregroundStyle(glucoseTextColor) + Text(trendArrow).foregroundStyle(.primary)
    }

    var cornerMainText: String {
        switch kind {
        case .iob: return displayedState.iob
        case .gauge: return glucoseText
        case .chart,
             .glucose: return glucoseWithArrow
        case .loop: return loopTimeText
        }
    }

    var loopFreshness: ComplicationState.LoopFreshness {
        isPlaceholder ? .unknown : displayedState.loopFreshness(at: referenceDate)
    }

    var loopColor: Color {
        switch loopFreshness {
        case .fresh: return Self.loopGreen
        case .late: return Self.loopYellow
        case .overdue: return Self.loopRed
        case .unknown: return Self.staleText
        }
    }

    /// The slash tells red from green without color.
    var loopSymbol: String { loopFreshness == .overdue ? "iphone.slash" : "iphone" }

    var loopTimeText: String {
        guard !isPlaceholder, let time = displayedState.loopTime(at: referenceDate) else { return ComplicationState.missingValue }
        return time.formatted(.timeOfDay.hour(.defaultDigits(amPM: .omitted)))
    }

    var ageText: String {
        if isPlaceholder { return "\(ComplicationState.missingValue) min" }
        return "\(displayedState.minutesAgo(at: referenceDate)) min"
    }

    var iobText: String { displayedState.iob == ComplicationState.missingValue ? displayedState.iob : "\(displayedState.iob) U" }
    var cobText: String { displayedState.cob == ComplicationState.missingValue ? displayedState.cob : "\(displayedState.cob) g" }

    var secondaryText: String {
        isStale ? ageText : displayedState.plainText(for: displayedState.secondaryValue)
    }

    var secondaryTextBesideArrow: String {
        isStale ? ageText : displayedState.plainText(for: displayedState.secondaryValue, withArrow: trendArrow.isEmpty)
    }

    var cornerText: String {
        isStale ? ageText : displayedState.labelledText(for: displayedState.cornerValue, withArrow: trendArrow.isEmpty)
    }

    var gaugeValue: Double {
        displayedState.gaugeValue ?? (displayedState.gaugeRange.lowerBound + displayedState.gaugeRange.upperBound) / 2
    }

    var gaugeGradient: Gradient {
        if isStale || !fullColor || displayedState.gaugeValue == nil {
            return Gradient(colors: [Self.staleText, Self.staleText])
        }
        let stops = (displayedState.ringStops ?? []).compactMap { stop in
            Color(complicationHex: stop.colorHex).map { Gradient.Stop(color: $0, location: stop.location) }
        }
        guard !stops.isEmpty else { return Self.neutralRing }
        return Gradient(stops: stops)
    }
}

private struct GlucoseRingGauge: View {
    let model: ComplicationModel
    let fontSize: CGFloat

    var body: some View {
        Gauge(value: model.gaugeValue, in: model.displayedState.gaugeRange) {
            Text("BG")
        } currentValueLabel: {
            Text(model.glucoseText)
                .font(.system(size: fontSize, weight: .bold))
                .minimumScaleFactor(0.5)
                .foregroundStyle(model.glucoseTextColor)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(model.gaugeGradient)
    }
}

private struct LabelledValue: View {
    let model: ComplicationModel
    let label: String
    let value: String
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(model.dimColor)
            Text(value)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(model.valueColor)
        }
    }
}

struct ComplicationCircularContent: View {
    let model: ComplicationModel

    var body: some View {
        Group {
            switch model.kind {
            case .chart,
                 .glucose:
                glucose
            case .gauge:
                GlucoseRingGauge(model: model, fontSize: 16)
            case .iob:
                iob
            case .loop:
                loop
            }
        }
        .fontDesign(.rounded)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var loop: some View {
        VStack(spacing: 1) {
            Image(systemName: model.loopSymbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(model.loopColor)
            Text(model.loopTimeText)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 2)
    }

    private var glucose: some View {
        VStack(spacing: -2) {
            Text(model.glucoseText)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(model.glucoseTextColor)
            Text(model.secondaryText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(model.dimColor)
        }
        .padding(.horizontal, 2)
    }

    private var iob: some View {
        VStack(spacing: -1) {
            Text("IOB")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(model.dimColor)
            Text(model.displayedState.iob)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(model.valueColor)
            Text(model.statusLine)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(model.dimColor)
        }
        .padding(.horizontal, 2)
    }
}

struct ComplicationCornerMain: View {
    let model: ComplicationModel

    var body: some View {
        Group {
            switch model.kind {
            case .loop:
                Image(systemName: model.loopSymbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(model.loopColor)
            case .iob:
                Text(model.cornerMainText).foregroundStyle(model.valueColor)
            case .gauge:
                Text(model.cornerMainText).foregroundStyle(model.glucoseTextColor)
            case .chart,
                 .glucose:
                model.glucoseWithArrowText
            }
        }
        .font(.system(size: 20, weight: .bold, design: .rounded))
        .minimumScaleFactor(0.6)
        .lineLimit(1)
    }
}

struct ComplicationCornerLabel: View {
    let model: ComplicationModel

    var body: some View {
        switch model.kind {
        case .gauge:
            Gauge(value: model.gaugeValue, in: model.displayedState.gaugeRange) {
                Text("BG")
            } currentValueLabel: {
                Text(model.glucoseText)
            } minimumValueLabel: {
                Text(model.displayedState.gaugeRange.lowerBound, format: .number.precision(.fractionLength(0)))
            } maximumValueLabel: {
                Text(model.displayedState.gaugeRange.upperBound, format: .number.precision(.fractionLength(0)))
            }
            .tint(model.gaugeGradient)
        case .iob:
            Text(
                model.isStale || model.isLoopStale
                    ? model.statusLine
                    : "COB \(model.cobText) · \(model.glucoseText)"
            )
        case .chart,
             .glucose:
            Text(model.cornerText)
        case .loop:
            Text("Loop \(model.loopTimeText)")
        }
    }
}

struct ComplicationRectangularContent: View {
    let model: ComplicationModel

    var body: some View {
        Group {
            switch model.kind {
            case .glucose:
                glucose
            case .gauge:
                gauge
            case .iob:
                iob
            case .chart:
                chart
            case .loop:
                loop
            }
        }
        .fontDesign(.rounded)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var glucoseLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(model.glucoseText)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(model.glucoseTextColor)
            if !model.isStale {
                Text(model.displayedState.trendArrow)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(model.displayedState.delta)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(model.dimColor)
            }
        }
    }

    private var ageLine: some View {
        Text("\(model.ageText) ago · loop \(model.displayedState.lastLoopTime)")
            .font(.system(size: 11))
            .foregroundStyle(model.dimColor)
    }

    private var glucose: some View {
        VStack(alignment: .leading, spacing: 1) {
            glucoseLine
            Text("IOB \(model.iobText) · COB \(model.cobText)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(model.valueColor)
            ageLine
        }
    }

    private var gauge: some View {
        HStack(spacing: 8) {
            GlucoseRingGauge(model: model, fontSize: 14)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.secondaryText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(model.valueColor)
                Text("IOB \(model.iobText)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(model.valueColor)
                Text("COB \(model.cobText)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(model.dimColor)
            }
            Spacer(minLength: 0)
        }
    }

    private var iob: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                LabelledValue(model: model, label: "IOB", value: model.iobText, size: 22)
                LabelledValue(model: model, label: "COB", value: model.cobText, size: 22)
            }
            HStack(spacing: 4) {
                model.glucoseWithArrowText
                    .font(.system(size: 14, weight: .bold))
                Text(
                    model.isStale
                        ? "\(model.ageText) ago"
                        : "\(model.displayedState.delta) · loop \(model.displayedState.lastLoopTime)"
                )
                .font(.system(size: 11))
                .foregroundStyle(model.loopLineColor)
            }
        }
    }

    private var loop: some View {
        HStack(spacing: 8) {
            Image(systemName: model.loopSymbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(model.loopColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Last loop")
                    .font(.system(size: 13, weight: .semibold))
                Text(model.loopTimeText)
                    .font(.system(size: 22, weight: .bold))
            }
            Spacer(minLength: 0)
        }
    }

    private var chart: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                model.glucoseWithArrowText
                    .font(.system(size: 20, weight: .bold))
                Text(model.secondaryTextBesideArrow)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(model.dimColor)
                Text(
                    model.displayedState.secondaryValue == .iob
                        ? "COB \(model.displayedState.cob)"
                        : "IOB \(model.displayedState.iob)"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(model.valueColor)
            }
            .minimumScaleFactor(0.6)
            .fixedSize(horizontal: true, vertical: false)
            ComplicationSparkline(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ComplicationInlineContent: View {
    let model: ComplicationModel

    var body: some View {
        if model.kind == .loop {
            Text(Image(systemName: model.loopSymbol)) + Text(" \(model.loopTimeText)")
        } else {
            Text(text)
        }
    }

    private var text: String {
        switch model.kind {
        case .iob:
            return model.isStale
                ? "IOB \(model.iobText) · \(model.ageText) ago"
                : "IOB \(model.iobText) · COB \(model.cobText) · \(model.glucoseWithArrow)"
        case .chart,
             .gauge,
             .glucose,
             .loop:
            return model.isStale
                ? "\(model.glucoseText) · \(model.ageText) ago"
                : "\(model.glucoseWithArrow) \(model.displayedState.delta) · IOB \(model.displayedState.iob)"
        }
    }
}

private struct ComplicationChartScale {
    private static let inset: CGFloat = 3

    let size: CGSize
    let timeRange: ClosedRange<TimeInterval>
    let valueRange: ClosedRange<Double>

    func horizontalPosition(of timestamp: TimeInterval) -> CGFloat {
        let elapsed = (timestamp - timeRange.lowerBound) / (timeRange.upperBound - timeRange.lowerBound)
        return Self.inset + CGFloat(elapsed) * (size.width - Self.inset * 2)
    }

    func verticalPosition(of glucose: Double) -> CGFloat {
        let fraction = (glucose - valueRange.lowerBound) / (valueRange.upperBound - valueRange.lowerBound)
        return Self.inset + CGFloat(1 - fraction) * (size.height - Self.inset * 2)
    }

    func position(of point: ComplicationPoint) -> CGPoint {
        CGPoint(x: horizontalPosition(of: point.timestamp), y: verticalPosition(of: point.glucose))
    }
}

struct ComplicationSparkline: View {
    let model: ComplicationModel

    private var history: [ComplicationPoint] { model.displayedState.history }
    private var band: ClosedRange<Double> { model.displayedState.inRangeBand }

    private var valueRange: ClosedRange<Double> {
        let values = history.map(\.glucose)
        let lowest = min(values.min() ?? band.lowerBound, band.lowerBound)
        let highest = max(values.max() ?? band.upperBound, band.upperBound)
        return lowest ... max(highest, lowest + model.displayedState.chartMinimumSpan)
    }

    private var timeRange: ClosedRange<TimeInterval> {
        let end = model.displayedState.date.timeIntervalSince1970
        return (end - ComplicationState.chartWindow) ... end
    }

    var body: some View {
        GeometryReader { geometry in
            if history.count >= 2 {
                chart(scale: ComplicationChartScale(size: geometry.size, timeRange: timeRange, valueRange: valueRange))
            } else {
                Text("no data")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(ComplicationModel.staleText)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    @ViewBuilder private func chart(scale: ComplicationChartScale) -> some View {
        inRangeBand(scale: scale)
        Path { $0.addLines(history.map(scale.position(of:))) }
            .stroke(model.glucoseColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        if let latest = history.last {
            Circle()
                .fill(model.glucoseColor)
                .frame(width: 4, height: 4)
                .position(scale.position(of: latest))
        }
    }

    private func inRangeBand(scale: ComplicationChartScale) -> some View {
        let top = scale.verticalPosition(of: band.upperBound)
        let bottom = scale.verticalPosition(of: band.lowerBound)
        return Rectangle()
            .fill(Color.primary.opacity(model.fullColor ? 0.12 : 0.2))
            .frame(width: scale.size.width, height: max(1, bottom - top))
            .position(x: scale.size.width / 2, y: (top + bottom) / 2)
    }
}

struct ComplicationPreview: View {
    let kind: ComplicationKind
    let slot: ComplicationSlot
    let state: ComplicationState

    private static let watchBackground = Color(white: 0.12)

    private var model: ComplicationModel {
        ComplicationModel(kind: kind, state: state, rendering: ComplicationRendering(referenceDate: state.date))
    }

    var body: some View {
        Group {
            switch slot {
            case .circular:
                circular
            case .rectangular:
                rectangular
            case .corner:
                corner
            case .inline:
                EmptyView()
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var circular: some View {
        ZStack {
            Circle().fill(Self.watchBackground)
            ComplicationCircularContent(model: model)
                .padding(4)
        }
        .frame(width: 66, height: 66)
    }

    private var rectangular: some View {
        ComplicationRectangularContent(model: model)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: 172, height: 66)
            .background(RoundedRectangle(cornerRadius: 12).fill(Self.watchBackground))
    }

    private var corner: some View {
        VStack(spacing: 2) {
            ComplicationCornerMain(model: model)
            cornerLabel
        }
        .padding(6)
        .frame(width: 80, height: 66)
        .background(RoundedRectangle(cornerRadius: 12).fill(Self.watchBackground))
    }

    @ViewBuilder private var cornerLabel: some View {
        if kind == .gauge {
            Gauge(value: model.gaugeValue, in: state.gaugeRange) { EmptyView() }
                .gaugeStyle(.accessoryLinear)
                .tint(model.gaugeGradient)
                .frame(width: 56)
        } else {
            ComplicationCornerLabel(model: model)
                .font(.system(size: 9, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }
}
