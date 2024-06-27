import Foundation

struct Oref2_variables: JSON, Equatable {
    var average_total_data: Decimal
    var weightedAverage: Decimal
    var past2hoursAverage: Decimal
    var date: Date
    var isEnabled: Bool
    var presetActive: Bool
    var overridePercentage: Decimal
    var useOverride: Bool
    var duration: Decimal
    var unlimited: Bool
    var hbt: Decimal
    var overrideTarget: Decimal
    var smbIsOff: Bool
    var advancedSettings: Bool
    var isfAndCr: Bool
    var isf: Bool
    var cr: Bool
    var smbIsScheduledOff: Bool
    var start: Decimal
    var end: Decimal
    var smbMinutes: Decimal
    var uamMinutes: Decimal

    init(
        average_total_data: Decimal,
        weightedAverage: Decimal,
        past2hoursAverage: Decimal,
        date: Date,
        isEnabled: Bool,
        presetActive: Bool,
        overridePercentage: Decimal,
        useOverride: Bool,
        duration: Decimal,
        unlimited: Bool,
        hbt: Decimal,
        overrideTarget: Decimal,
        smbIsOff: Bool,
        advancedSettings: Bool,
        isfAndCr: Bool,
        isf: Bool,
        cr: Bool,
        smbIsScheduledOff: Bool,
        start: Decimal,
        end: Decimal,
        smbMinutes: Decimal,
        uamMinutes: Decimal
    ) {
        self.average_total_data = average_total_data
        self.weightedAverage = weightedAverage
        self.past2hoursAverage = past2hoursAverage
        self.date = date
        self.isEnabled = isEnabled
        self.presetActive = presetActive
        self.overridePercentage = overridePercentage
        self.useOverride = useOverride
        self.duration = duration
        self.unlimited = unlimited
        self.hbt = hbt
        self.overrideTarget = overrideTarget
        self.smbIsOff = smbIsOff
        self.advancedSettings = advancedSettings
        self.isfAndCr = isfAndCr
        self.isf = isf
        self.cr = cr
        self.smbIsScheduledOff = smbIsScheduledOff
        self.start = start
        self.end = end
        self.smbMinutes = smbMinutes
        self.uamMinutes = uamMinutes
    }
}

extension Oref2_variables {
    private enum CodingKeys: String, CodingKey {
        case average_total_data
        case weightedAverage
        case past2hoursAverage
        case date
        case isEnabled
        case presetActive
        case overridePercentage
        case useOverride
        case duration
        case unlimited
        case hbt
        case overrideTarget
        case smbIsOff
        case advancedSettings
        case isfAndCr
        case isf
        case cr
        case smbIsScheduledOff
        case start
        case end
        case smbMinutes
        case uamMinutes
    }
}
