import Foundation

public struct TrioCustomOrefVariables: JSON, Equatable {
    public var average_total_data: Decimal
    public var currentTDD: Decimal
    public var weightedAverage: Decimal
    public var past2hoursAverage: Decimal
    public var date: Date
    public var overridePercentage: Decimal
    public var useOverride: Bool
    public var duration: Decimal
    public var unlimited: Bool
    public var overrideTarget: Decimal
    public var smbIsOff: Bool
    public var advancedSettings: Bool
    public var isfAndCr: Bool
    public var isf: Bool
    public var cr: Bool
    public var smbIsScheduledOff: Bool
    public var start: Decimal
    public var end: Decimal
    public var smbMinutes: Decimal
    public var uamMinutes: Decimal

    public init(
        average_total_data: Decimal,
        weightedAverage: Decimal,
        currentTDD: Decimal,
        past2hoursAverage: Decimal,
        date: Date,
        overridePercentage: Decimal,
        useOverride: Bool,
        duration: Decimal,
        unlimited: Bool,
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
        self.currentTDD = currentTDD
        self.past2hoursAverage = past2hoursAverage
        self.date = date
        self.overridePercentage = overridePercentage
        self.useOverride = useOverride
        self.duration = duration
        self.unlimited = unlimited
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

extension TrioCustomOrefVariables {
    private enum CodingKeys: String, CodingKey {
        case average_total_data
        case weightedAverage
        case currentTDD
        case past2hoursAverage
        case date
        case overridePercentage
        case useOverride
        case duration
        case unlimited
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
