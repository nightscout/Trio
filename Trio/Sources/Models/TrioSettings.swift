import Foundation

enum BolusShortcutLimit: String, JSON, CaseIterable, Identifiable {
    var id: String { rawValue }
    case notAllowed
    case limitBolusMax

    var displayName: String {
        switch self {
        case .notAllowed:
            return String(localized: "Not allowed")
        case .limitBolusMax:
            return String(localized: "Max bolus")
        }
    }
}

struct TrioSettings: JSON, Equatable, Encodable {
    var units: GlucoseUnits = .mgdL
    var closedLoop: Bool = false
    var isUploadEnabled: Bool = false
    var isDownloadEnabled: Bool = false
    var useLocalGlucoseSource: Bool = false
    var localGlucosePort: Int = 8080
    var debugOptions: Bool = false
    var cgm: CGMType = .none
    var cgmPluginIdentifier: String = ""
    var uploadGlucose: Bool = true
    var useCalendar: Bool = false
    var displayCalendarIOBandCOB: Bool = false
    var displayCalendarEmojis: Bool = false
    var glucoseBadge: Bool = false
    var notificationsPump: Bool = true
    var notificationsCgm: Bool = true
    var notificationsCarb: Bool = true
    var notificationsAlgorithm: Bool = true
    var glucoseNotificationsOption: GlucoseNotificationsOption = .onlyAlarmLimits
    var addSourceInfoToGlucoseNotifications: Bool = false
    var lowGlucose: Decimal = 72
    var highGlucose: Decimal = 270
    var carbsRequiredThreshold: Decimal = 10
    var showCarbsRequiredBadge: Bool = true
    var useFPUconversion: Bool = true
    var individualAdjustmentFactor: Decimal = 0.5
    var timeCap: Decimal = 8
    var minuteInterval: Decimal = 30
    var delay: Decimal = 60
    var useAppleHealth: Bool = false
    var smoothGlucose: Bool = false
    var eA1cDisplayUnit: EstimatedA1cDisplayUnit = .percent
    var high: Decimal = 180
    var low: Decimal = 70
    var glucoseColorScheme: GlucoseColorScheme = .staticColor
    var xGridLines: Bool = true
    var yGridLines: Bool = true
    var hideInsulinBadge: Bool = false
    var allowDilution: Bool = false
    var insulinConcentration: Decimal = 1
    var showCobIobChart: Bool = true
    var rulerMarks: Bool = true
    var forecastDisplayType: ForecastDisplayType = .cone
    var maxCarbs: Decimal = 250
    var maxFat: Decimal = 250
    var maxProtein: Decimal = 250
    var confirmBolusFaster: Bool = false
    var overrideFactor: Decimal = 0.8
    var fattyMeals: Bool = false
    var fattyMealFactor: Decimal = 0.7
    var sweetMeals: Bool = false
    var sweetMealFactor: Decimal = 1
    var displayPresets: Bool = true
    var confirmBolus: Bool = false
    var useLiveActivity: Bool = false
    var lockScreenView: LockScreenView = .simple
    var smartStackView: LockScreenView = .simple
    var bolusShortcut: BolusShortcutLimit = .notAllowed
    var timeInRangeType: TimeInRangeType = .timeInTightRange

    /// Selected Garmin watchface (Trio or SwissAlpine)
    var garminWatchface: GarminWatchface = .trio
    var garminDatafield: GarminDatafield = .none

    /// Primary attribute choice for Garmin display (COB, ISF, or Sensitivity Ratio)
    var primaryAttributeChoice: GarminPrimaryAttributeChoice = .cob

    /// Secondary attribute choice for Garmin display (TBR or Eventual BG)
    var secondaryAttributeChoice: GarminSecondaryAttributeChoice = .tbr

    /// Controls whether watchface data transmission is enabled
    var isWatchfaceDataEnabled: Bool = false

    /// Computed property that groups all Garmin settings into a single struct
    var garminSettings: GarminWatchSettings {
        get {
            GarminWatchSettings(
                watchface: garminWatchface,
                datafield: garminDatafield,
                primaryAttributeChoice: primaryAttributeChoice,
                secondaryAttributeChoice: secondaryAttributeChoice,
                isWatchfaceDataEnabled: isWatchfaceDataEnabled
            )
        }
        set {
            garminWatchface = newValue.watchface
            garminDatafield = newValue.datafield
            primaryAttributeChoice = newValue.primaryAttributeChoice
            secondaryAttributeChoice = newValue.secondaryAttributeChoice
            isWatchfaceDataEnabled = newValue.isWatchfaceDataEnabled
        }
    }
}

extension TrioSettings: Decodable {
    /// Custom decoder to handle incomplete JSON and provide default values for missing fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var settings = TrioSettings()

        if let units = try? container.decode(GlucoseUnits.self, forKey: .units) {
            settings.units = units
        }

        if let closedLoop = try? container.decode(Bool.self, forKey: .closedLoop) {
            settings.closedLoop = closedLoop
        }

        if let isUploadEnabled = try? container.decode(Bool.self, forKey: .isUploadEnabled) {
            settings.isUploadEnabled = isUploadEnabled
        }

        if let isDownloadEnabled = try? container.decode(Bool.self, forKey: .isDownloadEnabled) {
            settings.isDownloadEnabled = isDownloadEnabled
        }

        if let useLocalGlucoseSource = try? container.decode(Bool.self, forKey: .useLocalGlucoseSource) {
            settings.useLocalGlucoseSource = useLocalGlucoseSource
        }

        if let localGlucosePort = try? container.decode(Int.self, forKey: .localGlucosePort) {
            settings.localGlucosePort = localGlucosePort
        }

        if let debugOptions = try? container.decode(Bool.self, forKey: .debugOptions) {
            settings.debugOptions = debugOptions
        }

        if let cgm = try? container.decode(CGMType.self, forKey: .cgm) {
            settings.cgm = cgm
        }

        if let cgmPluginIdentifier = try? container.decode(String.self, forKey: .cgmPluginIdentifier) {
            settings.cgmPluginIdentifier = cgmPluginIdentifier
        }

        if let uploadGlucose = try? container.decode(Bool.self, forKey: .uploadGlucose) {
            settings.uploadGlucose = uploadGlucose
        }

        if let useCalendar = try? container.decode(Bool.self, forKey: .useCalendar) {
            settings.useCalendar = useCalendar
        }

        if let displayCalendarIOBandCOB = try? container.decode(Bool.self, forKey: .displayCalendarIOBandCOB) {
            settings.displayCalendarIOBandCOB = displayCalendarIOBandCOB
        }

        if let displayCalendarEmojis = try? container.decode(Bool.self, forKey: .displayCalendarEmojis) {
            settings.displayCalendarEmojis = displayCalendarEmojis
        }

        if let useAppleHealth = try? container.decode(Bool.self, forKey: .useAppleHealth) {
            settings.useAppleHealth = useAppleHealth
        }

        if let glucoseBadge = try? container.decode(Bool.self, forKey: .glucoseBadge) {
            settings.glucoseBadge = glucoseBadge
        }

        if let useFPUconversion = try? container.decode(Bool.self, forKey: .useFPUconversion) {
            settings.useFPUconversion = useFPUconversion
        }

        if let individualAdjustmentFactor = try? container.decode(Decimal.self, forKey: .individualAdjustmentFactor) {
            settings.individualAdjustmentFactor = individualAdjustmentFactor
        }

        if let fattyMeals = try? container.decode(Bool.self, forKey: .fattyMeals) {
            settings.fattyMeals = fattyMeals
        }

        if let fattyMealFactor = try? container.decode(Decimal.self, forKey: .fattyMealFactor) {
            settings.fattyMealFactor = fattyMealFactor
        }

        if let sweetMeals = try? container.decode(Bool.self, forKey: .sweetMeals) {
            settings.sweetMeals = sweetMeals
        }

        if let sweetMealFactor = try? container.decode(Decimal.self, forKey: .sweetMealFactor) {
            settings.sweetMealFactor = sweetMealFactor
        }

        if let overrideFactor = try? container.decode(Decimal.self, forKey: .overrideFactor) {
            settings.overrideFactor = overrideFactor
        }

        if let timeCap = try? container.decode(Decimal.self, forKey: .timeCap) {
            settings.timeCap = timeCap
        }

        if let minuteInterval = try? container.decode(Decimal.self, forKey: .minuteInterval) {
            settings.minuteInterval = minuteInterval
        }

        if let delay = try? container.decode(Decimal.self, forKey: .delay) {
            settings.delay = delay
        }

        if let notificationsPump = try? container.decode(Bool.self, forKey: .notificationsPump) {
            settings.notificationsPump = notificationsPump
        }

        if let notificationsCgm = try? container.decode(Bool.self, forKey: .notificationsCgm) {
            settings.notificationsCgm = notificationsCgm
        }

        if let notificationsCarb = try? container.decode(Bool.self, forKey: .notificationsCarb) {
            settings.notificationsCarb = notificationsCarb
        }

        if let notificationsAlgorithm = try? container.decode(Bool.self, forKey: .notificationsAlgorithm) {
            settings.notificationsAlgorithm = notificationsAlgorithm
        }

        if let glucoseNotificationsOption = try? container.decode(
            GlucoseNotificationsOption.self,
            forKey: .glucoseNotificationsOption
        ) {
            settings.glucoseNotificationsOption = glucoseNotificationsOption
        }

        if let addSourceInfoToGlucoseNotifications = try? container.decode(
            Bool.self,
            forKey: .addSourceInfoToGlucoseNotifications
        ) {
            settings.addSourceInfoToGlucoseNotifications = addSourceInfoToGlucoseNotifications
        }

        if let lowGlucose = try? container.decode(Decimal.self, forKey: .lowGlucose) {
            settings.lowGlucose = lowGlucose
        }

        if let highGlucose = try? container.decode(Decimal.self, forKey: .highGlucose) {
            settings.highGlucose = highGlucose
        }

        if let carbsRequiredThreshold = try? container.decode(Decimal.self, forKey: .carbsRequiredThreshold) {
            settings.carbsRequiredThreshold = carbsRequiredThreshold
        }

        if let showCarbsRequiredBadge = try? container.decode(Bool.self, forKey: .showCarbsRequiredBadge) {
            settings.showCarbsRequiredBadge = showCarbsRequiredBadge
        }

        if let smoothGlucose = try? container.decode(Bool.self, forKey: .smoothGlucose) {
            settings.smoothGlucose = smoothGlucose
        }

        if let low = try? container.decode(Decimal.self, forKey: .low) {
            settings.low = low
        }

        if let high = try? container.decode(Decimal.self, forKey: .high) {
            settings.high = high
        }

        if let glucoseColorScheme = try? container.decode(GlucoseColorScheme.self, forKey: .glucoseColorScheme) {
            settings.glucoseColorScheme = glucoseColorScheme
        }

        if let xGridLines = try? container.decode(Bool.self, forKey: .xGridLines) {
            settings.xGridLines = xGridLines
        }

        if let yGridLines = try? container.decode(Bool.self, forKey: .yGridLines) {
            settings.yGridLines = yGridLines
        }

        if let showCobIobChart = try? container.decode(Bool.self, forKey: .showCobIobChart) {
            settings.showCobIobChart = showCobIobChart
        }

        if let hideInsulinBadge = try? container.decode(Bool.self, forKey: .hideInsulinBadge) {
            settings.hideInsulinBadge = hideInsulinBadge
        }

        if let allowDilution = try? container.decode(Bool.self, forKey: .allowDilution) {
            settings.allowDilution = allowDilution
        }

        if let insulinConcentration = try? container.decode(Decimal.self, forKey: .insulinConcentration) {
            settings.insulinConcentration = insulinConcentration
        }

        if let rulerMarks = try? container.decode(Bool.self, forKey: .rulerMarks) {
            settings.rulerMarks = rulerMarks
        }

        if let forecastDisplayType = try? container.decode(ForecastDisplayType.self, forKey: .forecastDisplayType) {
            settings.forecastDisplayType = forecastDisplayType
        }

        if let eA1cDisplayUnit = try? container.decode(EstimatedA1cDisplayUnit.self, forKey: .eA1cDisplayUnit) {
            settings.eA1cDisplayUnit = eA1cDisplayUnit
        }

        if let maxCarbs = try? container.decode(Decimal.self, forKey: .maxCarbs) {
            settings.maxCarbs = maxCarbs
        }

        if let maxFat = try? container.decode(Decimal.self, forKey: .maxFat) {
            settings.maxFat = maxFat
        }

        if let maxProtein = try? container.decode(Decimal.self, forKey: .maxProtein) {
            settings.maxProtein = maxProtein
        }

        if let confirmBolusFaster = try? container.decode(Bool.self, forKey: .confirmBolusFaster) {
            settings.confirmBolusFaster = confirmBolusFaster
        }

        if let displayPresets = try? container.decode(Bool.self, forKey: .displayPresets) {
            settings.displayPresets = displayPresets
        }

        if let confirmBolus = try? container.decode(Bool.self, forKey: .confirmBolus) {
            settings.confirmBolus = confirmBolus
        }

        if let useLiveActivity = try? container.decode(Bool.self, forKey: .useLiveActivity) {
            settings.useLiveActivity = useLiveActivity
        }

        if let lockScreenView = try? container.decode(LockScreenView.self, forKey: .lockScreenView) {
            settings.lockScreenView = lockScreenView
        }

        if let smartStackView = try? container.decode(LockScreenView.self, forKey: .smartStackView) {
            settings.smartStackView = smartStackView
        }

        if let bolusShortcut = try? container.decode(BolusShortcutLimit.self, forKey: .bolusShortcut) {
            settings.bolusShortcut = bolusShortcut
        }

        if let timeInRangeType = try? container.decode(TimeInRangeType.self, forKey: .timeInRangeType) {
            settings.timeInRangeType = timeInRangeType
        }

        if let garminWatchface = try? container.decode(GarminWatchface.self, forKey: .garminWatchface) {
            settings.garminWatchface = garminWatchface
        }

        if let garminDatafield = try? container.decode(GarminDatafield.self, forKey: .garminDatafield) {
            settings.garminDatafield = garminDatafield
        }

        if let primaryAttributeChoice = try? container
            .decode(GarminPrimaryAttributeChoice.self, forKey: .primaryAttributeChoice)
        {
            settings.primaryAttributeChoice = primaryAttributeChoice
        }

        if let secondaryAttributeChoice = try? container.decode(
            GarminSecondaryAttributeChoice.self,
            forKey: .secondaryAttributeChoice
        ) {
            settings.secondaryAttributeChoice = secondaryAttributeChoice
        }

        if let isWatchfaceDataEnabled = try? container.decode(Bool.self, forKey: .isWatchfaceDataEnabled) {
            settings.isWatchfaceDataEnabled = isWatchfaceDataEnabled
        }

        self = settings
    }
}
