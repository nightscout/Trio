import Foundation

extension UserDefaults {
    private enum Keys {
        static let liveActivityOrder = "liveActivityOrder"
    }

    func loadLiveActivityOrderFromUserDefaults() -> [LiveActivityAttributes.LiveActivityItem]? {
        if let itemStrings = stringArray(forKey: Keys.liveActivityOrder) {
            return itemStrings.map { string in
                if string == "" {
                    return .empty
                } else {
                    return LiveActivityAttributes.LiveActivityItem(rawValue: string) ?? .empty
                }
            }
        }
        return nil
    }
}

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
        settings: TrioSettings,
        determination: DeterminationData?,
        override: OverrideData?,
        widgetItems: [LiveActivityAttributes.LiveActivityItem]?
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

        let detailedState: LiveActivityAttributes.ContentAdditionalState?

        switch settings.lockScreenView {
        case .detailed:
            let chartBG = chart.map { Decimal($0.glucose) }
            let chartDate = chart.map(\.date)

            /// glucose limits from UI settings, not from notifications settings
            detailedState = LiveActivityAttributes.ContentAdditionalState(
                chart: chartBG,
                chartDate: chartDate,
                rotationDegrees: rotationDegrees,
                cob: Decimal(determination?.cob ?? 0),
                iob: determination?.iob ?? 0 as Decimal,
                tdd: determination?.tdd ?? 0 as Decimal,
                isOverrideActive: override?.isActive ?? false,
                overrideName: override?.overrideName ?? "Override",
                overrideDate: override?.date ?? Date(),
                overrideDuration: override?.duration ?? 0,
                overrideTarget: override?.target ?? 0,
                widgetItems: widgetItems ?? [] // set empty array here to silence compiler; this can never be nil
            )

        case .simple:
            detailedState = nil
        }

        self.init(
            unit: settings.units.rawValue,
            bg: formattedBG,
            direction: trendString,
            change: change,
            date: determination?.date ?? nil,
            highGlucose: settings.high,
            lowGlucose: settings.low,
            target: determination?.target ?? 100 as Decimal,
            glucoseColorScheme: settings.glucoseColorScheme.rawValue,
            detailedViewState: detailedState,
            isInitialState: false
        )
    }
}
