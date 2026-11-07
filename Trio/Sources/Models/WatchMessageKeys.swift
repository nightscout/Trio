enum WatchMessageKeys {
    // Request/Response Keys
    static let date = "date"
    static let units = "units"
    static let requestWatchUpdate = "requestWatchUpdate"
    static let watchState = "watchState"
    static let acknowledged = "acknowledged"
    static let ackCode = "ackCode"
    static let message = "message"

    // Treatment Keys
    static let bolus = "bolus"
    static let carbs = "carbs"
    static let cancelBolus = "cancelBolus"
    static let bolusCanceled = "bolusCanceled"
    static let bolusProgress = "bolusProgress"
    static let activeBolusAmount = "activeBolusAmount"
    static let deliveredAmount = "deliveredAmount"
    static let bolusProgressTimestamp = "bolusProgressTimestamp"

    // Recommendation Keys
    static let requestBolusRecommendation = "requestBolusRecommendation"
    static let recommendedBolus = "recommendedBolus"

    // Override Keys
    static let cancelOverride = "cancelOverride"
    static let activateOverride = "activateOverride"

    // Temp Target Keys
    static let cancelTempTarget = "cancelTempTarget"
    static let activateTempTarget = "activateTempTarget"

    // Watch State Data Keys
    static let currentGlucose = "currentGlucose"
    static let currentGlucoseColorString = "currentGlucoseColorString"
    static let trend = "trend"
    static let delta = "delta"
    static let iob = "iob"
    static let cob = "cob"
    static let lastLoopTime = "lastLoopTime"
    static let glucoseValues = "glucoseValues"
    static let minYAxisValue = "minYAxisValue"
    static let maxYAxisValue = "maxYAxisValue"
    static let overridePresets = "overridePresets"
    static let tempTargetPresets = "tempTargetPresets"

    // Limits and Settings Keys
    static let maxBolus = "maxBolus"
    static let maxCarbs = "maxCarbs"
    static let maxFat = "maxFat"
    static let maxProtein = "maxProtein"
    static let bolusIncrement = "bolusIncrement"
    static let confirmBolusFaster = "confirmBolusFaster"

    // Notification Actions
    static let snoozeDuration = "snoozeDuration"
    static let snoozeUntilDate = "snoozeUntilDate"

    // Forecast
    static let showForecastWatch = "showForecastWatch"
    /// Whether the watch's own urgent low alarm should use Critical Alerts.
    static let useCriticalAlertsWatch = "useCriticalAlertsWatch"
    /// Latest CGM export for the watch's own sensor link; can be absent while the phone is starting.
    static let watchSensorConfiguration = "watchSensorConfiguration"
    /// The CGM's Read on Apple Watch; independent of whether the phone's CGM manager is loaded yet.
    static let watchReadsSensor = "watchReadsSensor"
    /// mg/dL bounds, target and color scheme the watch colors its own readings by.
    static let glucoseRangeLow = "glucoseRangeLow"
    static let glucoseRangeHigh = "glucoseRangeHigh"
    static let glucoseRangeTarget = "glucoseRangeTarget"
    static let glucoseColorScheme = "glucoseColorScheme"
    /// mg/dL of the phone's glucose alarms that are on, the most cautious of each; 0: none.
    static let glucoseAlarmUrgentLow = "glucoseAlarmUrgentLow"
    static let glucoseAlarmLow = "glucoseAlarmLow"
    static let glucoseAlarmHigh = "glucoseAlarmHigh"
    static let isForecastCone = "isForecastCone"
    static let forecastData = "forecastData"
    static let forecastStartDate = "forecastStartDate"
    static let forecastConeMin = "forecastConeMin"
    static let forecastConeMax = "forecastConeMax"
    static let forecastLines = "forecastLines"
}
