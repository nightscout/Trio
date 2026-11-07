import SwiftUI

enum ComplicationKind: String, CaseIterable, Identifiable {
    case glucose
    case gauge
    case iob
    case chart

    var id: String { rawValue }

    var widgetKind: String {
        switch self {
        case .glucose: return "TrioGlucoseComplication"
        case .gauge: return "TrioGaugeComplication"
        case .iob: return "TrioIobComplication"
        case .chart: return "TrioChartComplication"
        }
    }

    var displayName: String {
        switch self {
        case .glucose: return String(localized: "Trio Glucose", comment: "Name of the glucose watch complication")
        case .gauge: return String(localized: "Trio Gauge", comment: "Name of the glucose ring watch complication")
        case .iob: return String(localized: "Trio IOB", comment: "Name of the insulin on board watch complication")
        case .chart: return String(localized: "Trio Chart", comment: "Name of the glucose chart watch complication")
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
                localized: "Insulin on board first, with COB and glucose alongside. Fixed layout; only Grey Out After applies.",
                comment: "Description of the insulin on board watch complication"
            )
        case .chart:
            return String(
                localized: "Glucose, the Small Line and IOB next to the last three hours of readings. Rectangular slots only.",
                comment: "Description of the glucose chart watch complication"
            )
        }
    }

    var slots: [ComplicationSlot] {
        switch self {
        case .chart: return [.rectangular]
        case .gauge: return [.corner, .circular, .rectangular]
        case .glucose,
             .iob: return [.corner, .circular, .rectangular, .inline]
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
    private static let highWarningSpan = 0.15

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
        if isStale { return .gray }
        return fullColor ? displayedState.glucoseColor : .primary
    }

    var valueColor: Color { isStale || isLoopStale || isLoopUnknown ? .gray : .primary }

    var statusLine: String {
        if isStale { return ageText }
        if isLoopStale { return "loop \(displayedState.lastLoopTime)" }
        return "COB \(displayedState.cob)"
    }

    var dimColor: Color { isStale ? .gray : .secondary }

    var trendArrow: String { isStale ? "" : displayedState.trendArrow }

    var glucoseText: String {
        isStale ? ComplicationState.missingValue : displayedState.glucose
    }

    var glucoseWithArrow: String {
        trendArrow.isEmpty ? glucoseText : "\(glucoseText)\(trendArrow)"
    }

    var cornerMainText: String {
        switch kind {
        case .iob: return displayedState.iob
        case .gauge: return glucoseText
        case .chart,
             .glucose: return glucoseWithArrow
        }
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

    var cornerText: String {
        isStale ? ageText : displayedState.labelledText(for: displayedState.cornerValue)
    }

    var gaugeValue: Double {
        displayedState.gaugeValue ?? (displayedState.gaugeRange.lowerBound + displayedState.gaugeRange.upperBound) / 2
    }

    var gaugeGradient: Gradient {
        if isStale || !fullColor || displayedState.gaugeValue == nil {
            return Gradient(colors: [.gray, .gray])
        }
        return Gradient(stops: ringStops)
    }

    private var ringStops: [Gradient.Stop] {
        let range = displayedState.gaugeRange
        let span = range.upperBound - range.lowerBound
        let fraction: (Double) -> Double = { value in
            min(max((value - range.lowerBound) / span, 0), 1)
        }
        let low = fraction(displayedState.inRangeBand.lowerBound)
        let high = fraction(displayedState.inRangeBand.upperBound)
        return [
            .init(color: .red, location: 0),
            .init(color: .green, location: low),
            .init(color: .green, location: high),
            .init(color: .orange, location: min(high + Self.highWarningSpan, 1)),
            .init(color: .red, location: 1)
        ]
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
                .foregroundStyle(model.glucoseColor)
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
            }
        }
        .fontDesign(.rounded)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var glucose: some View {
        VStack(spacing: -2) {
            Text(model.glucoseText)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(model.glucoseColor)
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
        Text(model.cornerMainText)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .foregroundStyle(model.kind == .iob ? model.valueColor : model.glucoseColor)
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
                .foregroundStyle(model.glucoseColor)
            if !model.isStale {
                Text(model.displayedState.trendArrow)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(model.glucoseColor)
                Text(model.displayedState.delta)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ageLine: some View {
        Text("\(model.ageText) ago · loop \(model.displayedState.lastLoopTime)")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
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
                Text(model.glucoseWithArrow)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(model.glucoseColor)
                Text(
                    model.isStale
                        ? "\(model.ageText) ago"
                        : "\(model.displayedState.delta) · loop \(model.displayedState.lastLoopTime)"
                )
                .font(.system(size: 11))
                .foregroundStyle(model.isLoopStale || model.isLoopUnknown ? Color.gray : Color.secondary)
            }
        }
    }

    private var chart: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.glucoseWithArrow)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(model.glucoseColor)
                Text(model.secondaryText)
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
        Text(text)
    }

    private var text: String {
        switch model.kind {
        case .iob:
            return model.isStale
                ? "IOB \(model.iobText) · \(model.ageText) ago"
                : "IOB \(model.iobText) · COB \(model.cobText) · \(model.glucoseWithArrow)"
        case .chart,
             .gauge,
             .glucose:
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
                    .foregroundStyle(.secondary)
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

    private var model: ComplicationModel {
        ComplicationModel(kind: kind, state: state, rendering: ComplicationRendering(referenceDate: state.date))
    }

    var body: some View {
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

    private var circular: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.14))
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
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.14)))
    }

    private var corner: some View {
        VStack(spacing: 2) {
            ComplicationCornerMain(model: model)
            cornerLabel
        }
        .padding(6)
        .frame(width: 80, height: 66)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.14)))
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
