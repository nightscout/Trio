import Foundation

extension Profile {
    /// Updates profile properties from preferences where CodingKeys match
    /// This function ended up being pretty ugly, but I couldn't think of a cleaner
    /// way. I considered converting to JSON or using Mirror, but these weren't
    /// great so in the end I think that this approach is simpliest.
    ///
    /// Also, this implementation does _not_ copy any of the optional properties
    /// since these should get set in the `generate` method.
    mutating func update(from preferences: Preferences) {
        // Decimal properties
        maxIob = preferences.maxIOB
        min5mCarbImpact = preferences.min5mCarbimpact
        maxCOB = preferences.maxCOB
        maxDailySafetyMultiplier = preferences.maxDailySafetyMultiplier
        currentBasalSafetyMultiplier = preferences.currentBasalSafetyMultiplier
        autosensMax = preferences.autosensMax
        autosensMin = preferences.autosensMin
        halfBasalExerciseTarget = preferences.halfBasalExerciseTarget
        remainingCarbsCap = preferences.remainingCarbsCap
        smbInterval = preferences.smbInterval
        maxSMBBasalMinutes = preferences.maxSMBBasalMinutes
        maxUAMSMBBasalMinutes = preferences.maxUAMSMBBasalMinutes
        bolusIncrement = preferences.bolusIncrement
        carbsReqThreshold = preferences.carbsReqThreshold
        remainingCarbsFraction = preferences.remainingCarbsFraction
        enableSMBHighBgTarget = preferences.enableSMB_high_bg_target
        maxDeltaBgThreshold = preferences.maxDeltaBGthreshold
        insulinPeakTime = preferences.insulinPeakTime
        noisyCGMTargetMultiplier = preferences.noisyCGMTargetMultiplier
        adjustmentFactor = preferences.adjustmentFactor
        adjustmentFactorSigmoid = preferences.adjustmentFactorSigmoid
        weightPercentage = preferences.weightPercentage
        thresholdSetting = preferences.threshold_setting
        maxMealAbsorptionTime = preferences.maxMealAbsorptionTime
        smbDeliveryRatio = preferences.smbDeliveryRatio

        // Bool properties
        highTemptargetRaisesSensitivity = preferences.highTemptargetRaisesSensitivity
        lowTemptargetLowersSensitivity = preferences.lowTemptargetLowersSensitivity
        sensitivityRaisesTarget = preferences.sensitivityRaisesTarget
        resistanceLowersTarget = preferences.resistanceLowersTarget
        skipNeutralTemps = preferences.skipNeutralTemps
        enableUAM = preferences.enableUAM
        a52RiskEnable = preferences.a52RiskEnable
        enableSMBWithCOB = preferences.enableSMBWithCOB
        enableSMBWithTemptarget = preferences.enableSMBWithTemptarget
        allowSMBWithHighTemptarget = preferences.allowSMBWithHighTemptarget
        enableSMBAlways = preferences.enableSMBAlways
        enableSMBAfterCarbs = preferences.enableSMBAfterCarbs
        rewindResetsAutosens = preferences.rewindResetsAutosens
        unsuspendIfNoTemp = preferences.unsuspendIfNoTemp
        enableSMBHighBg = preferences.enableSMB_high_bg
        useCustomPeakTime = preferences.useCustomPeakTime
        suspendZerosIob = preferences.suspendZerosIOB
        useNewFormula = preferences.useNewFormula
        sigmoid = preferences.sigmoid
        tddAdjBasal = preferences.tddAdjBasal

        // Enum properties
        curve = preferences.curve
    }
}

enum ProfileGenerator {
    /// This function is a port of the prepare/profile.js function from Trio, and it calls the core OpenAPS function
    static func generate(
        pumpSettings: PumpSettings,
        bgTargets: BGTargets,
        basalProfile: [BasalProfileEntry],
        isf: InsulinSensitivities,
        preferences: Preferences,
        carbRatios: CarbRatios,
        tempTargets: [TempTarget],
        model: String,
        trioSettings _: TrioSettings
    ) throws -> Profile {
        let model = model.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !carbRatios.schedule.isEmpty else {
            throw ProfileError.invalidCarbRatio
        }

        var preferences = preferences
        switch (preferences.curve, preferences.useCustomPeakTime) {
        case (.rapidActing, true):
            preferences.insulinPeakTime = max(50, min(preferences.insulinPeakTime, 120))
        case (.rapidActing, false):
            preferences.insulinPeakTime = 75
        case (.ultraRapid, true):
            preferences.insulinPeakTime = max(35, min(preferences.insulinPeakTime, 100))
        case (.ultraRapid, false):
            preferences.insulinPeakTime = 55
        default:
            // don't do anything
            debug(.openAPS, "don't modify insulin peak time")
        }

        return try generate(
            pumpSettings: pumpSettings,
            bgTargets: bgTargets,
            basalProfile: basalProfile,
            isf: isf,
            preferences: preferences,
            carbRatios: carbRatios,
            tempTargets: tempTargets,
            model: model
        )
    }

    /// Direct port of the OpenAPS profile generate function
    private static func generate(
        pumpSettings: PumpSettings,
        bgTargets: BGTargets,
        basalProfile: [BasalProfileEntry],
        isf: InsulinSensitivities,
        preferences: Preferences,
        carbRatios: CarbRatios,
        tempTargets: [TempTarget],
        model: String
    ) throws -> Profile {
        var profile = Profile() // start with the defaults

        // check if inputs has overrides for any of the default prefs
        // and apply if applicable. Note, this comes from the generate/profile.js
        // where preferences get copied to the input then in the generate function
        // where it checks the input for properties that match the defaults
        profile.update(from: preferences)

        // in the Javascript version this check is for 1, but in Trio
        // the minimum dia you can set with the UI is 5
        guard pumpSettings.insulinActionCurve >= 5 else {
            throw ProfileError.invalidDIA(value: pumpSettings.insulinActionCurve)
        }
        profile.dia = pumpSettings.insulinActionCurve

        profile.model = model
        profile.skipNeutralTemps = preferences.skipNeutralTemps

        profile.currentBasal = try Basal.basalLookup(basalProfile)
        profile.basalprofile = basalProfile

        let basalProfile = basalProfile
            .map { BasalProfileEntry(start: $0.start, minutes: $0.minutes, rate: $0.rate.rounded(scale: 3)) }

        profile.maxDailyBasal = Basal.maxDailyBasal(basalProfile)
        profile.maxBasal = pumpSettings.maxBasal

        // Error check: profile.currentBasal === 0 in Javascript
        if let currentBasal = profile.currentBasal {
            guard currentBasal != 0 else {
                throw ProfileError.invalidCurrentBasal(value: profile.currentBasal)
            }
        }

        // Error check: profile.max_daily_basal === 0 in Javascript
        if let maxDailyBasal = profile.maxDailyBasal {
            guard maxDailyBasal != 0 else {
                throw ProfileError.invalidMaxDailyBasal(value: profile.maxDailyBasal)
            }
        }

        // Error check: profile.max_basal < 0.1 in Javascript
        if let maxBasal = profile.maxBasal {
            guard maxBasal >= 0.1 else {
                throw ProfileError.invalidMaxBasal(value: profile.maxBasal)
            }
        }

        profile.outUnits = bgTargets.userPreferredUnits
        let (updatedTargets, range) = try Targets.bgTargetsLookup(targets: bgTargets, tempTargets: tempTargets, profile: profile)
        profile.minBg = range.minBg?.rounded()
        profile.maxBg = range.maxBg?.rounded()
        // Note: we're using updatedTargets here because in Javascript the bgTargetsLookup
        // function mutates the input, so we want the mutated version in the
        // profile and we need to round the properties
        let roundedTargets = updatedTargets.targets.map { target -> ComputedBGTargetEntry in
            ComputedBGTargetEntry(
                low: target.low.rounded(),
                high: target.high.rounded(),
                start: target.start,
                offset: target.offset,
                maxBg: target.maxBg?.rounded(),
                minBg: target.minBg?.rounded(),
                temptargetSet: target.temptargetSet
            )
        }

        // Set the rounded targets on the profile
        profile.bgTargets = ComputedBGTargets(
            units: updatedTargets.units,
            userPreferredUnits: updatedTargets.userPreferredUnits,
            targets: roundedTargets
        )

        profile.temptargetSet = range.temptargetSet
        let (sens, isfUpdated) = try Isf.isfLookup(isfDataInput: isf)
        profile.sens = sens
        profile.isfProfile = isfUpdated

        // Error check: profile.sens < 5 in Javascript
        if let sens = profile.sens {
            guard sens >= 5 else {
                debug(.openAPS, "ISF of \(String(describing: profile.sens)) is not supported")
                throw ProfileError.invalidISF(value: profile.sens)
            }
        }

        // Handle carb ratio data
        guard let currentCarbRatio = Carbs.carbRatioLookup(carbRatio: carbRatios) else {
            throw ProfileError.invalidCarbRatio
        }
        profile.carbRatio = currentCarbRatio
        profile.carbRatios = carbRatios

        return profile
    }
}
