import Foundation

extension UserDefaults {
    private enum Keys {
        static let liveActivityOrder = "liveActivityOrder"
    }

    func loadLiveActivityOrderFromUserDefaults() -> [String]? {
        array(forKey: Keys.liveActivityOrder) as? [String]
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
                highGlucose: settings.high,
                lowGlucose: settings.low,
                target: determination?.target ?? 0 as Decimal,
                cob: Decimal(determination?.cob ?? 0),
                iob: determination?.iob ?? 0 as Decimal,
                unit: settings.units.rawValue,
                isOverrideActive: override?.isActive ?? false,
                overrideName: override?.overrideName ?? "Override"
            )

        case .simple:
            detailedState = nil
        }

        let itemOrder = UserDefaults.standard
            .loadLiveActivityOrderFromUserDefaults() ?? ["currentGlucose", "iob", "cob", "updatedLabel"]

        self.init(
            bg: formattedBG,
            direction: trendString,
            change: change,
            date: bg.date,
            detailedViewState: detailedState,
            showCOB: settings.showCOB,
            showIOB: settings.showIOB,
            showCurrentGlucose: settings.showCurrentGlucose,
            showUpdatedLabel: settings.showUpdatedLabel,
            itemOrder: itemOrder,
            isInitialState: false
        )
    }
}
