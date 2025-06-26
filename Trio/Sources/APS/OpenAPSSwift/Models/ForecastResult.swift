import Foundation

struct ForecastResult {
    public let iob: [Decimal]
    public let cob: [Decimal]
    public let uam: [Decimal]
    public let zt: [Decimal]
    public let eventualGlucose: Decimal
    public let minForecastedGlucose: Decimal
    public let minGuardGlucose: Decimal
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
