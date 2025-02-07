extension OpenAPS {
    enum Bundle {
        static let iob = "bundle/iob.js"
        static let meal = "bundle/meal.js"
        static let autotunePrep = "bundle/autotune-prep.js"
        static let autotuneCore = "bundle/autotune-core.js"
        static let getLastGlucose = "bundle/glucose-get-last.js"
        static let basalSetTemp = "bundle/basal-set-temp.js"
        static let determineBasal = "bundle/determine-basal.js"
        static let autosens = "bundle/autosens.js"
        static let profile = "bundle/profile.js"
    }

    enum Prepare {
        static let iob = "prepare/iob.js"
        static let meal = "prepare/meal.js"
        static let autotunePrep = "prepare/autotune-prep.js"
        static let autotuneCore = "prepare/autotune-core.js"
        static let determineBasal = "prepare/determine-basal.js"
        static let autosens = "prepare/autosens.js"
        static let profile = "prepare/profile.js"
        static let log = "prepare/log.js"
    }

    enum Middleware {
        static let determineBasal = "middleware/determine_basal.js"
    }

    enum Settings {
        static let preferences = "preferences.json"
        static let autotune = "settings/autotune.json"
        static let autosense = "settings/autosense.json"
        static let profile = "settings/profile.json"
        static let pumpProfile = "settings/pumpprofile.json"
        static let settings = "settings/settings.json"
        static let bgTargets = "settings/bg_targets.json"
        static let insulinSensitivities = "settings/insulin_sensitivities.json"
        static let basalProfile = "settings/basal_profile.json"
        static let carbRatios = "settings/carb_ratios.json"
        static let tempTargets = "settings/temptargets.json"
        static let model = "settings/model.json"
    }

    enum Monitor {
        static let pumpHistory = "monitor/pumphistory-24h-zoned.json"
        static let reservoir = "monitor/reservoir.json"
        static let carbHistory = "monitor/carbhistory.json"
        static let clock = "monitor/clock-zoned.json"
        static let status = "monitor/status.json"
        static let tempBasal = "monitor/temp_basal.json"
        static let meal = "monitor/meal.json"
        static let glucose = "monitor/glucose.json"
        static let iob = "monitor/iob.json"
        static let cgmState = "monitor/cgm-state.json"
        static let podAge = "monitor/pod-age.json"
        static let oref2_variables = "monitor/oref2_variables.json"
        static let alertHistory = "monitor/alerthistory.json"
        static let statistics = "monitor/statistics.json"
    }

    enum Enact {
        static let suggested = "enact/suggested.json"
        static let enacted = "enact/enacted.json"
    }

    enum Upload {
        static let nsStatus = "upload/ns-status.json"
        static let latestTreatments = "upload/latest-treatments.json"
        static let recentPumphistory = "upload/recent-pumphistory.json"
    }

    enum Function {
        static let freeaps = "freeaps"
        static let generate = "generate"
        static let tempBasalFunctions = "tempBasalFunctions"
        static let exportDefaults = "exportDefaults"
    }

    enum Nightscout {
        static let uploadedPumphistory = "upload/uploaded-pumphistory.json"
        static let uploadedCarbs = "upload/uploaded-carbs.json"
        static let uploadedTempTargets = "upload/uploaded-temptargets.json"
        static let uploadedGlucose = "upload/uploaded-glucose.json"
        static let uploadedCGMState = "upload/uploaded-cgm-state.json"
        static let uploadedPodAge = "upload/uploaded-pod-age.json"
        static let uploadedProfile = "upload/uploaded-profile.json"
        static let uploadedPreferences = "upload/uploaded-preferences.json"
        static let uploadedSettings = "upload/uploaded-settings.json"
        static let uploadedManualGlucose = "upload/uploaded-manual-readings.json"
        static let uploadedNotes = "upload/uploaded-notes.json"
    }

    enum Trio {
        static let settings = "freeaps/freeaps_settings.json"
        static let tempTargetsPresets = "freeaps/temptargets_presets.json"
        static let calibrations = "freeaps/calibrations.json"
    }
}
