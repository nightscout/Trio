import Foundation

struct IOBForecast {
    let forecasts: [Decimal] // The final, trimmed array for output
    let minGuardGlucose: Decimal // The absolute min of the untrimmed array
    let minForecastGlucose: Decimal // The min after the initial 90-min peak
    let maxForecastGlucose: Decimal // The absolute max of the untrimmed array
}

struct COBForecast {
    let forecasts: [Decimal] // The final, trimmed array for output
    let minGuardGlucose: Decimal // The absolute min of the untrimmed array
    let minForecastGlucose: Decimal // The min after the initial 90-min peak
    let maxForecastGlucose: Decimal // The absolute max of the untrimmed array
}

struct UAMForecast {
    let forecasts: [Decimal] // The final, trimmed array for output
    let minGuardGlucose: Decimal // The absolute min of the untrimmed array
    let minForecastGlucose: Decimal // The min after the initial 60-min peak
    let maxForecastGlucose: Decimal // The absolute max of the untrimmed array
    let duration: Decimal // The calculated UAM duration in hours
}

struct ZTForecast {
    let forecasts: [Decimal] // The final, trimmed array for output
    let minGuardGlucose: Decimal // The absolute min of the untrimmed array
}

struct IndividualForecast {
    let forecasts: [Decimal]
    let minGuardGlucose: Decimal
    let rawForecasts: [Decimal]
    let duration: Decimal? // only set by UAM
}

struct AllForecasts {
    let iob: IOBForecast
    let zt: ZTForecast
    let cob: COBForecast
    let uam: UAMForecast
}
