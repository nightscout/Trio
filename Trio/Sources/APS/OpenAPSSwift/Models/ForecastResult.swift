import Foundation

struct ForecastResult {
    public let iob: [Decimal]
    public let cob: [Decimal]?
    public let uam: [Decimal]?
    public let zt: [Decimal]
    public let internalCob: [Decimal] // non optional, used downstream
    public let internalUam: [Decimal] // non optional, used downstream
    public let eventualGlucose: Decimal
    public let minForecastedGlucose: Decimal
    public let minIOBForecastedGlucose: Decimal
    public let minGuardGlucose: Decimal
    public let carbImpact: Decimal
    public let remainingCarbImpactPeak: Decimal
    public let adjustedCarbRatio: Decimal
}

struct ForecastSelectionResult {
    let minIOBForecastGlucose: Decimal
    let minCOBForecastGlucose: Decimal
    let minUAMForecastGlucose: Decimal
    let minIOBGuardGlucose: Decimal
    let minCOBGuardGlucose: Decimal
    let minUAMGuardGlucose: Decimal
    let minZTGuardGlucose: Decimal
    let maxIOBForecastGlucose: Decimal
    let maxCOBForecastGlucose: Decimal
    let maxUAMForecastGlucose: Decimal
    let lastIOBForecastGlucose: Decimal
    let lastCOBForecastGlucose: Decimal
    let lastUAMForecastGlucose: Decimal
    let lastZTForecastGlucose: Decimal
}

struct ForecastBlendingResult {
    let minForecastedGlucose: Decimal
    let avgForecastedGlucose: Decimal
    let minGuardGlucose: Decimal
}
