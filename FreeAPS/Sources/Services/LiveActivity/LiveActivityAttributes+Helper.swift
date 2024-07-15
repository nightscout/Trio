import Foundation

extension LiveActivityAttributes.ContentState {
    static func formatGlucose(_ value: Int, units: GlucoseUnits, forceSign: Bool) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        if forceSign {
            formatter.positivePrefix = formatter.plusSign
        }
        formatter.roundingMode = .halfUp

        return formatter
            .string(from: units == .mmolL ? value.asMmolL as NSNumber : NSNumber(value: value))!
    }

    static func calculateChange(chart: [GlucoseData], units: GlucoseUnits) -> String {
        guard chart.count > 2 else { return "" }
        let lastGlucose = chart.first?.glucose ?? 0
        let secondLastGlucose = chart.dropFirst().first?.glucose ?? 0
        let delta = lastGlucose - secondLastGlucose
        let deltaAsDecimal = units == .mmolL ? Decimal(delta).asMmolL : Decimal(delta)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        if units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        formatter.positivePrefix = "  +"
        formatter.negativePrefix = "  -"
        return formatter.string(from: deltaAsDecimal as NSNumber) ?? "--"
    }

    init?(
        new bg: GlucoseData,
        prev _: GlucoseData?,
        units: GlucoseUnits,
        chart: [GlucoseData],
        settings: FreeAPSSettings,
        determination: DeterminationData?,
        override: OverrideData?
    ) {
        let glucose = bg.glucose
        let formattedBG = Self.formatGlucose(Int(glucose), units: units, forceSign: false)
        var rotationDegrees: Double = 0.0

        switch bg.direction {
        case .doubleUp,
             .singleUp,
             .tripleUp:
            rotationDegrees = -90
        case .fortyFiveUp:
            rotationDegrees = -45
        case .flat:
            rotationDegrees = 0
        case .fortyFiveDown:
            rotationDegrees = 45
        case .doubleDown,
             .singleDown,
             .tripleDown:
            rotationDegrees = 90
        case nil,
             .notComputable,
             .rateOutOfRange:
            rotationDegrees = 0
        default:
            rotationDegrees = 0
        }

        let trendString = bg.direction?.symbol as? String
        let change = Self.calculateChange(chart: chart, units: units)
        let chartBG = chart.map(\.glucose)
        let conversionFactor: Double = settings.units == .mmolL ? 18.0 : 1.0
        let convertedChartBG = chartBG.map { Double($0) / conversionFactor }
        let chartDate = chart.map(\.date)

        /// glucose limits from UI settings, not from notifications settings
        let highGlucose = settings.high / Decimal(conversionFactor)
        let lowGlucose = settings.low / Decimal(conversionFactor)
        let cob = determination?.cob ?? 0
        let iob = determination?.iob ?? 0
        let lockScreenView = settings.lockScreenView.displayName
        let unit = settings.units == .mmolL ? " mmol/L" : " mg/dL"
        let isOverrideActive = override?.isActive ?? false

        self.init(
            bg: formattedBG,
            direction: trendString,
            change: change,
            date: bg.date,
            chart: convertedChartBG,
            chartDate: chartDate,
            rotationDegrees: rotationDegrees,
            highGlucose: Double(highGlucose),
            lowGlucose: Double(lowGlucose),
            cob: Decimal(cob),
            iob: iob as Decimal,
            lockScreenView: lockScreenView,
            unit: unit,
            isOverrideActive: isOverrideActive
        )
    }
}
