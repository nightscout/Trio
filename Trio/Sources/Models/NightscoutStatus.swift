import Foundation

struct NightscoutStatus: JSON {
    let device: String
    let openaps: OpenAPSStatus
    let pump: NSPumpStatus
    let uploader: Uploader
}

struct OpenAPSStatus: JSON {
    let iob: IOBEntry?
    let suggested: Determination?
    let enacted: Determination?
    let version: String
    let recommendedBolus: Decimal?
    /// Raw value, not the localized name: followers parse this.
    let dosingMode: String
    /// The IOB projection whose first value is `iob`.
    var iobForecast: NightscoutIOBForecast? = nil
}

/// IOB and insulin activity every five minutes from `iob.time`, for the
/// insulin already delivered and the running temp basal until it ends.
struct NightscoutIOBForecast: JSON {
    let iob: [Decimal]
    /// U/min, like `IOBEntry.activity`.
    let activity: [Decimal]

    init(_ entries: [IOBEntry]) {
        iob = entries.map { $0.iob.rounded(toPlaces: 3) }
        activity = entries.map { $0.activity.rounded(toPlaces: 5) }
    }
}

struct NSPumpStatus: JSON {
    let clock: Date
    let battery: Battery?
    let reservoir: Decimal?
    let status: PumpStatus?
    let bolusIncrement: Decimal
}

struct Uploader: JSON {
    let batteryVoltage: Decimal?
    let battery: Int
    let isCharging: Bool?
}

struct NightscoutTimevalue: JSON {
    let time: String
    let value: Decimal
    let timeAsSeconds: Int?
}

struct ScheduledNightscoutProfile: JSON {
    let dia: Decimal
    let carbs_hr: Int
    let delay: Decimal
    let timezone: String
    let target_low: [NightscoutTimevalue]
    let target_high: [NightscoutTimevalue]
    let sens: [NightscoutTimevalue]
    let basal: [NightscoutTimevalue]
    let carbratio: [NightscoutTimevalue]
    let units: String
}

struct NightscoutProfileStore: JSON {
    let defaultProfile: String
    let startDate: Date
    let mills: Int
    let units: String
    let enteredBy: String
    let store: [String: ScheduledNightscoutProfile]
    let bundleIdentifier: String
    let deviceToken: String
    let isAPNSProduction: Bool
    let overridePresets: [NightscoutPresetOverride]?
    let teamID: String
    let expirationDate: Date?
    /// Remote command types this build accepts; followers hide unsupported actions.
    let remoteCommands: [String]?
    var profileEditLimits: NightscoutProfileEditLimits? = nil
    /// Default is named by its store key.
    var scheduledSwitches: [ScheduledProfileSwitch]? = nil
    var scheduledSwitchesFingerprint: String? = nil
}

/// The values a remote profile editor may offer, glucose in `units`.
struct NightscoutProfileEditLimits: JSON, Equatable {
    struct Limit: JSON, Equatable {
        let min: Decimal
        let max: Decimal
        let step: Decimal
    }

    let units: String
    let maxBasal: Decimal
    let basalRates: [Decimal]
    let basalMinimum: Decimal?
    let carbRatio: Limit
    let sensitivity: Limit
    let target: Limit
    let maxSegments: Int
    let segmentSeconds: Int

    init(units: GlucoseUnits, basalLimits: TherapyBasalLimits) {
        /// mmol/L bounds are the outermost 0.1 steps that convert back to whole mg/dL within the range.
        func glucoseLimit(_ range: TherapyProfileLimits.Range) -> Limit {
            guard units == .mmolL else { return Limit(min: range.min, max: range.max, step: range.step) }
            var min = range.min.asMmolL
            while min.asMgdL < range.min { min += 0.1 }
            var max = range.max.asMmolL
            while max.asMgdL > range.max { max -= 0.1 }
            return Limit(min: min, max: max, step: 0.1)
        }
        let rates = basalLimits.allowedRates.map { $0.rounded(toPlaces: 3) }
        self.units = units == .mmolL ? "mmol/L" : "mg/dL"
        maxBasal = basalLimits.maxBasal
        basalRates = rates
        basalMinimum = rates.first
        carbRatio = Limit(
            min: TherapyProfileLimits.carbRatio.min,
            max: TherapyProfileLimits.carbRatio.max,
            step: TherapyProfileLimits.carbRatio.step
        )
        sensitivity = glucoseLimit(TherapyProfileLimits.sensitivity)
        target = glucoseLimit(TherapyProfileLimits.target)
        maxSegments = TherapyProfileLimits.maxSegments
        segmentSeconds = TherapyProfileLimits.segmentSeconds
    }
}

extension ScheduledNightscoutProfile {
    /// Glucose values in `units`.
    init(profile: TrioTherapyProfile, units: GlucoseUnits, dia: Decimal, min5mCarbimpact: Decimal, timezone: String) {
        func timeValue(_ seconds: Int, _ value: Decimal) -> NightscoutTimevalue {
            NightscoutTimevalue(
                time: String(TrioTherapyProfile.startString(seconds: seconds).prefix(5)),
                value: value,
                timeAsSeconds: seconds
            )
        }
        var carbsHr: Decimal = 0
        if let isf = profile.sensitivity.first?.value, let cr = profile.carbRatio.first?.value, isf > 0, cr > 0 {
            carbsHr = min5mCarbimpact * 12 / isf * cr
            carbsHr = Decimal(round(Double(carbsHr) * 10.0)) / 10
        }
        self.init(
            dia: dia,
            carbs_hr: Int(carbsHr),
            delay: 0,
            timezone: timezone,
            target_low: profile.target.map { timeValue($0.seconds, $0.low.asUnit(units)) },
            target_high: profile.target.map { timeValue($0.seconds, $0.high.asUnit(units)) },
            sens: profile.sensitivity.map { timeValue($0.seconds, $0.value.asUnit(units)) },
            basal: profile.basal.map { timeValue($0.seconds, $0.value) },
            carbratio: profile.carbRatio.map { timeValue($0.seconds, $0.value) },
            units: units == .mmolL ? "mmol" : "mg/dl"
        )
    }

    /// One entry per profile, keyed by its store key.
    static func store(
        profiles: [TrioTherapyProfile],
        units: GlucoseUnits,
        dia: Decimal,
        min5mCarbimpact: Decimal,
        timezone: String
    ) -> [String: ScheduledNightscoutProfile] {
        Dictionary(uniqueKeysWithValues: profiles.map { profile in
            (
                profile.storeKey,
                ScheduledNightscoutProfile(
                    profile: profile,
                    units: units,
                    dia: dia,
                    min5mCarbimpact: min5mCarbimpact,
                    timezone: timezone
                )
            )
        })
    }
}

struct NightscoutPresetOverride: JSON {
    let name: String
    let duration: Decimal?
    let percentage: Double?
    let target: Decimal?
}
