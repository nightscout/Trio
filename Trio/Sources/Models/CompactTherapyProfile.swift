import Foundation

/// Profile values as remote commands send them: pairs of `[secondsFromMidnight, value]`, targets as
/// `[seconds, low, high]`, glucose in `units`.
struct CompactTherapyProfile: Codable, Equatable, Sendable {
    let units: String
    let basal: [[Double]]
    let carbratio: [[Double]]
    let sens: [[Double]]
    let target: [[Double]]

    var glucoseUnits: GlucoseUnits? {
        switch units.lowercased() {
        case "mg/dl",
             "mgdl": return .mgdL
        case "mmol",
             "mmol/l",
             "mmoll": return .mmolL
        default: return nil
        }
    }

    /// The profile in mg/dL. Malformed entries throw `TherapyProfileError.invalidValues`. A glucose value in mmol/L that
    /// equals `original`'s value at the same start time, shown in mmol/L, keeps `original`'s mg/dL value.
    func therapyProfile(named name: String, original: TrioTherapyProfile? = nil) throws -> TrioTherapyProfile {
        guard let glucoseUnits else {
            throw TherapyProfileError.invalidValues(String(localized: "Unknown glucose units \(units)."))
        }

        func seconds(_ value: Double) throws -> Int {
            guard value.isFinite, value == value.rounded(), value >= 0, value < 86400 else {
                throw TherapyProfileError.invalidValues(String(localized: "Invalid start time \(value.formatted())."))
            }
            return Int(value)
        }

        func decimal(_ value: Double) throws -> Decimal {
            guard value.isFinite, let converted = Decimal(string: value.description) else {
                throw TherapyProfileError.invalidValues(String(localized: "Invalid value \(value.formatted())."))
            }
            return converted
        }

        func glucose(_ value: Double, originalValue: Decimal?) throws -> Decimal {
            let value = try decimal(value)
            guard glucoseUnits == .mmolL else { return value }
            if let originalValue, originalValue.asMmolL == value {
                return originalValue
            }
            return value.asMgdL
        }

        func pairs(_ rows: [[Double]], label: String, originalGlucose: [TherapyScheduleEntry]?) throws -> [TherapyScheduleEntry] {
            try rows.map { row in
                guard row.count == 2 else {
                    throw TherapyProfileError
                        .invalidValues(String(localized: "\(label): each entry needs a start time and a value."))
                }
                let start = try seconds(row[0])
                guard let originalGlucose else {
                    return TherapyScheduleEntry(seconds: start, value: try decimal(row[1]))
                }
                let originalValue = originalGlucose.first { $0.seconds == start }?.value
                return TherapyScheduleEntry(seconds: start, value: try glucose(row[1], originalValue: originalValue))
            }
        }

        let targets = try target.map { row -> TherapyTargetEntry in
            guard row.count == 3 else {
                throw TherapyProfileError
                    .invalidValues(String(localized: "Glucose Targets: each entry needs a start time, a low and a high value."))
            }
            let start = try seconds(row[0])
            let originalTarget = original?.target.first { $0.seconds == start }
            return TherapyTargetEntry(
                seconds: start,
                low: try glucose(row[1], originalValue: originalTarget?.low),
                high: try glucose(row[2], originalValue: originalTarget?.high)
            )
        }

        return TrioTherapyProfile(
            name: name,
            basal: try pairs(basal, label: String(localized: "Basal Rates"), originalGlucose: nil),
            carbRatio: try pairs(carbratio, label: String(localized: "Carb Ratios"), originalGlucose: nil),
            sensitivity: try pairs(
                sens,
                label: String(localized: "Insulin Sensitivities"),
                originalGlucose: original?.sensitivity ?? []
            ),
            target: targets
        )
    }
}
