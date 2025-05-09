import Foundation
import HealthKit
import LoopKit

struct BloodGlucose: JSON, Identifiable, Hashable, Codable {
    enum Direction: String, JSON {
        case tripleUp = "TripleUp"
        case doubleUp = "DoubleUp"
        case singleUp = "SingleUp"
        case fortyFiveUp = "FortyFiveUp"
        case flat = "Flat"
        case fortyFiveDown = "FortyFiveDown"
        case singleDown = "SingleDown"
        case doubleDown = "DoubleDown"
        case tripleDown = "TripleDown"
        case none = "NONE"
        case notComputable = "NOT COMPUTABLE"
        case rateOutOfRange = "RATE OUT OF RANGE"

        init?(from string: String) {
            switch string {
            case "\u{2191}\u{2191}\u{2191}",
                 "TripleUp":
                self = .tripleUp
            case "\u{2191}\u{2191}",
                 "DoubleUp":
                self = .doubleUp
            case "\u{2191}",
                 "SingleUp":
                self = .singleUp
            case "\u{2197}",
                 "FortyFiveUp":
                self = .fortyFiveUp
            case "\u{2192}",
                 "Flat":
                self = .flat
            case "\u{2198}",
                 "FortyFiveDown":
                self = .fortyFiveDown
            case "\u{2193}",
                 "SingleDown":
                self = .singleDown
            case "\u{2193}\u{2193}",
                 "DoubleDown":
                self = .doubleDown
            case "\u{2193}\u{2193}\u{2193}",
                 "TripleDown":
                self = .tripleDown
            case "\u{2194}",
                 "NONE":
                self = .none
            case "NOT COMPUTABLE":
                self = .notComputable
            case "RATE OUT OF RANGE":
                self = .rateOutOfRange
            default:
                return nil
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case _id
        case sgv
        case direction
        case date
        case dateString
        case unfiltered
        case filtered
        case noise
        case glucose
        case type
        case activationDate
        case sessionStartDate
        case transmitterID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _id = try container.decode(String.self, forKey: ._id)

        sgv = try? container.decodeIfPresent(Int.self, forKey: .sgv)
        if sgv == nil {
            // The nightscout API might return a double instead of an int, or the key might be missing
            if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: .sgv) {
                sgv = Int(doubleValue)
            }
            // If both attempts fail, sgv remains nil
        }

        direction = try container.decodeIfPresent(Direction.self, forKey: .direction)
        date = try container.decode(Decimal.self, forKey: .date)
        dateString = try container.decode(Date.self, forKey: .dateString)
        unfiltered = try container.decodeIfPresent(Decimal.self, forKey: .unfiltered)
        filtered = try container.decodeIfPresent(Decimal.self, forKey: .filtered)
        noise = try container.decodeIfPresent(Int.self, forKey: .noise)
        glucose = try container.decodeIfPresent(Int.self, forKey: .glucose)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        activationDate = try container.decodeIfPresent(Date.self, forKey: .activationDate)
        sessionStartDate = try container.decodeIfPresent(Date.self, forKey: .sessionStartDate)
        transmitterID = try container.decodeIfPresent(String.self, forKey: .transmitterID)
    }

    init(
        _id: String = UUID().uuidString,
        sgv: Int? = nil,
        direction: Direction? = nil,
        date: Decimal,
        dateString: Date,
        unfiltered: Decimal? = nil,
        filtered: Decimal? = nil,
        noise: Int? = nil,
        glucose: Int? = nil,
        type: String? = nil,
        activationDate: Date? = nil,
        sessionStartDate: Date? = nil,
        transmitterID: String? = nil
    ) {
        self._id = _id
        self.sgv = sgv
        self.direction = direction
        self.date = date
        self.dateString = dateString
        self.unfiltered = unfiltered
        self.filtered = filtered
        self.noise = noise
        self.glucose = glucose
        self.type = type
        self.activationDate = activationDate
        self.sessionStartDate = sessionStartDate
        self.transmitterID = transmitterID
    }

    var _id: String?
    var id: String {
        _id ?? UUID().uuidString
    }

    var sgv: Int?
    var direction: Direction?
    let date: Decimal
    let dateString: Date
    let unfiltered: Decimal?
    let filtered: Decimal?
    let noise: Int?
    var glucose: Int?
    var type: String? = nil
    var activationDate: Date? = nil
    var sessionStartDate: Date? = nil
    var transmitterID: String? = nil
    var isStateValid: Bool { sgv ?? 0 >= 39 && noise ?? 1 != 4 }

    static func == (lhs: BloodGlucose, rhs: BloodGlucose) -> Bool {
        lhs.dateString == rhs.dateString
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(dateString)
    }
}

enum GlucoseUnits: String, JSON, Equatable, CaseIterable, Identifiable {
    case mgdL = "mg/dL"
    case mmolL = "mmol/L"

    static let exchangeRate: Decimal = 0.0555

    var id: String { rawValue }
}

extension Int {
    var asMmolL: Decimal {
        Trio.rounded(Decimal(self) * GlucoseUnits.exchangeRate, scale: 1, roundingMode: .plain)
    }

    var formattedAsMmolL: String {
        NumberFormatter.glucoseFormatter.string(from: asMmolL as NSDecimalNumber) ?? "\(asMmolL)"
    }
}

extension Decimal {
    var asMmolL: Decimal {
        Trio.rounded(self * GlucoseUnits.exchangeRate, scale: 1, roundingMode: .plain)
    }

    var asMgdL: Decimal {
        Trio.rounded(self / GlucoseUnits.exchangeRate, scale: 0, roundingMode: .plain)
    }

    var formattedAsMmolL: String {
        NumberFormatter.glucoseFormatter.string(from: asMmolL as NSDecimalNumber) ?? "\(asMmolL)"
    }
}

extension Double {
    var asMmolL: Decimal {
        Trio.rounded(Decimal(self) * GlucoseUnits.exchangeRate, scale: 1, roundingMode: .plain)
    }

    var asMgdL: Decimal {
        Trio.rounded(Decimal(self) / GlucoseUnits.exchangeRate, scale: 0, roundingMode: .plain)
    }

    var formattedAsMmolL: String {
        NumberFormatter.glucoseFormatter.string(from: asMmolL as NSDecimalNumber) ?? "\(asMmolL)"
    }
}

extension NumberFormatter {
    static let glucoseFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

extension BloodGlucose: SavitzkyGolaySmoothable {
    var value: Double {
        get {
            Double(glucose ?? 0)
        }
        set {
            glucose = Int(newValue)
            sgv = Int(newValue)
        }
    }
}

extension BloodGlucose {
    func convertStoredGlucoseSample(isManualGlucose: Bool) -> StoredGlucoseSample {
        StoredGlucoseSample(
            syncIdentifier: id,
            startDate: dateString.date,
            quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double(glucose!)),
            wasUserEntered: isManualGlucose,
            device: HKDevice.local()
        )
    }
}
