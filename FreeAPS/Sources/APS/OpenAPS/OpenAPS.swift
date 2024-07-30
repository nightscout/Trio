import Combine
import CoreData
import Foundation
import JavaScriptCore

final class OpenAPS {
    private let jsWorker = JavaScriptWorker()
    private let processQueue = DispatchQueue(label: "OpenAPS.processQueue", qos: .utility)

    private let storage: FileStorage

    let coredataContext = CoreDataStack.shared.persistentContainer.viewContext // newBackgroundContext()

    init(storage: FileStorage) {
        self.storage = storage
    }

    func determineBasal(currentTemp: TempBasal, clock: Date = Date()) -> Future<Suggestion?, Never> {
        Future { promise in
            self.processQueue.async {
                debug(.openAPS, "Start determineBasal")
                // clock
                self.storage.save(clock, as: Monitor.clock)

                // temp_basal
                let tempBasal = currentTemp.rawJSON
                self.storage.save(tempBasal, as: Monitor.tempBasal)

                // meal
                let pumpHistory = self.loadFileFromStorage(name: OpenAPS.Monitor.pumpHistory)
                let carbs = self.loadFileFromStorage(name: Monitor.carbHistory)
                let glucose = self.loadFileFromStorage(name: Monitor.glucose)
                let profile = self.loadFileFromStorage(name: Settings.profile)
                let basalProfile = self.loadFileFromStorage(name: Settings.basalProfile)

                let meal = self.meal(
                    pumphistory: pumpHistory,
                    profile: profile,
                    basalProfile: basalProfile,
                    clock: clock,
                    carbs: carbs,
                    glucose: glucose
                )

                self.storage.save(meal, as: Monitor.meal)

                // iob
                let autosens = self.loadFileFromStorage(name: Settings.autosense)
                let iob = self.iob(
                    pumphistory: pumpHistory,
                    profile: profile,
                    clock: clock,
                    autosens: autosens.isEmpty ? .null : autosens
                )

                self.storage.save(iob, as: Monitor.iob)

                // determine-basal
                let reservoir = self.loadFileFromStorage(name: Monitor.reservoir)

                let preferences = self.loadFileFromStorage(name: Settings.preferences)

                // oref2
                let oref2_variables = self.oref2()

                let suggested = self.determineBasal(
                    glucose: glucose,
                    currentTemp: tempBasal,
                    iob: iob,
                    profile: profile,
                    autosens: autosens.isEmpty ? .null : autosens,
                    meal: meal,
                    microBolusAllowed: true,
                    reservoir: reservoir,
                    pumpHistory: pumpHistory,
                    preferences: preferences,
                    basalProfile: basalProfile,
                    oref2_variables: oref2_variables
                )
                debug(.openAPS, "SUGGESTED: \(suggested)")

                if var suggestion = Suggestion(from: suggested) {
                    suggestion.timestamp = suggestion.deliverAt ?? clock
                    self.storage.save(suggestion, as: Enact.suggested)

                    // MARK: Save to CoreData also. To do: Remove JSON saving

                    if suggestion.tdd ?? 0 > 0 {
                        self.coredataContext.perform {
                            let saveToTDD = TDD(context: self.coredataContext)

                            saveToTDD.timestamp = suggestion.timestamp ?? Date()
                            saveToTDD.tdd = (suggestion.tdd ?? 0) as NSDecimalNumber?
                            try? self.coredataContext.save()

                            let saveTarget = Target(context: self.coredataContext)
                            saveTarget.current = (suggestion.current_target ?? 100) as NSDecimalNumber?
                            try? self.coredataContext.save()
                        }

                        self.coredataContext.perform {
                            let saveToInsulin = InsulinDistribution(context: self.coredataContext)

                            saveToInsulin.bolus = (suggestion.insulin?.bolus ?? 0) as NSDecimalNumber?
                            saveToInsulin.scheduledBasal = (suggestion.insulin?.scheduled_basal ?? 0) as NSDecimalNumber?
                            saveToInsulin.tempBasal = (suggestion.insulin?.temp_basal ?? 0) as NSDecimalNumber?
                            saveToInsulin.date = Date()

                            try? self.coredataContext.save()
                        }
                    }

                    promise(.success(suggestion))
                } else {
                    promise(.success(nil))
                }
            }
        }
    }

    func oref2() -> RawJSON {
        coredataContext.performAndWait {
            let preferences = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)
            var hbt_ = preferences?.halfBasalExerciseTarget ?? 160
            let wp = preferences?.weightPercentage ?? 1
            let smbMinutes = (preferences?.maxSMBBasalMinutes ?? 30) as NSDecimalNumber
            let uamMinutes = (preferences?.maxUAMSMBBasalMinutes ?? 30) as NSDecimalNumber

            let tenDaysAgo = Date().addingTimeInterval(-10.days.timeInterval)
            let twoHoursAgo = Date().addingTimeInterval(-2.hours.timeInterval)

            var uniqueEvents = [TDD]()
            let requestTDD = TDD.fetchRequest() as NSFetchRequest<TDD>
            requestTDD.predicate = NSPredicate(format: "timestamp > %@ AND tdd > 0", tenDaysAgo as NSDate)
            let sortTDD = NSSortDescriptor(key: "timestamp", ascending: true)
            requestTDD.sortDescriptors = [sortTDD]
            try? uniqueEvents = coredataContext.fetch(requestTDD)

            var sliderArray = [TempTargetsSlider]()
            let requestIsEnbled = TempTargetsSlider.fetchRequest() as NSFetchRequest<TempTargetsSlider>
            let sortIsEnabled = NSSortDescriptor(key: "date", ascending: false)
            requestIsEnbled.sortDescriptors = [sortIsEnabled]
            // requestIsEnbled.fetchLimit = 1
            try? sliderArray = coredataContext.fetch(requestIsEnbled)

            var overrideArray = [Override]()
            let requestOverrides = Override.fetchRequest() as NSFetchRequest<Override>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            // requestOverrides.fetchLimit = 1
            try? overrideArray = coredataContext.fetch(requestOverrides)

            var tempTargetsArray = [TempTargets]()
            let requestTempTargets = TempTargets.fetchRequest() as NSFetchRequest<TempTargets>
            let sortTT = NSSortDescriptor(key: "date", ascending: false)
            requestTempTargets.sortDescriptors = [sortTT]
            requestTempTargets.fetchLimit = 1
            try? tempTargetsArray = coredataContext.fetch(requestTempTargets)

            let total = uniqueEvents.compactMap({ each in each.tdd as? Decimal ?? 0 }).reduce(0, +)
            var indeces = uniqueEvents.count
            // Only fetch once. Use same (previous) fetch
            let twoHoursArray = uniqueEvents.filter({ ($0.timestamp ?? Date()) >= twoHoursAgo })
            var nrOfIndeces = twoHoursArray.count
            let totalAmount = twoHoursArray.compactMap({ each in each.tdd as? Decimal ?? 0 }).reduce(0, +)

            var temptargetActive = tempTargetsArray.first?.active ?? false
            let isPercentageEnabled = sliderArray.first?.enabled ?? false

            var useOverride = overrideArray.first?.enabled ?? false
            var overridePercentage = Decimal(overrideArray.first?.percentage ?? 100)
            var unlimited = overrideArray.first?.indefinite ?? true
            var disableSMBs = overrideArray.first?.smbIsOff ?? false

            let currentTDD = (uniqueEvents.last?.tdd ?? 0) as Decimal

            if indeces == 0 {
                indeces = 1
            }
            if nrOfIndeces == 0 {
                nrOfIndeces = 1
            }

            let average2hours = totalAmount / Decimal(nrOfIndeces)
            let average14 = total / Decimal(indeces)

            let weight = wp
            let weighted_average = weight * average2hours + (1 - weight) * average14

            var duration: Decimal = 0
            var newDuration: Decimal = 0
            var overrideTarget: Decimal = 0

            if useOverride {
                duration = (overrideArray.first?.duration ?? 0) as Decimal
                overrideTarget = (overrideArray.first?.target ?? 0) as Decimal
                let advancedSettings = overrideArray.first?.advancedSettings ?? false
                let addedMinutes = Int(duration)
                let date = overrideArray.first?.date ?? Date()
                if date.addingTimeInterval(addedMinutes.minutes.timeInterval) < Date(),
                   !unlimited
                {
                    useOverride = false
                    let saveToCoreData = Override(context: self.coredataContext)
                    saveToCoreData.enabled = false
                    saveToCoreData.date = Date()
                    saveToCoreData.duration = 0
                    saveToCoreData.indefinite = false
                    saveToCoreData.percentage = 100
                    try? self.coredataContext.save()
                }
            }

            if !useOverride {
                unlimited = true
                overridePercentage = 100
                duration = 0
                overrideTarget = 0
                disableSMBs = false
            }

            if temptargetActive {
                var duration_ = 0
                var hbt = Double(hbt_)
                var dd = 0.0

                if temptargetActive {
                    duration_ = Int(truncating: tempTargetsArray.first?.duration ?? 0)
                    hbt = tempTargetsArray.first?.hbt ?? Double(hbt_)
                    let startDate = tempTargetsArray.first?.startDate ?? Date()
                    let durationPlusStart = startDate.addingTimeInterval(duration_.minutes.timeInterval)
                    dd = durationPlusStart.timeIntervalSinceNow.minutes

                    if dd > 0.1 {
                        hbt_ = Decimal(hbt)
                        temptargetActive = true
                    } else {
                        temptargetActive = false
                    }
                }
            }

            if currentTDD > 0 {
                let averages = Oref2_variables(
                    average_total_data: average14,
                    weightedAverage: weighted_average,
                    past2hoursAverage: average2hours,
                    date: Date(),
                    isEnabled: temptargetActive,
                    presetActive: isPercentageEnabled,
                    overridePercentage: overridePercentage,
                    useOverride: useOverride,
                    duration: duration,
                    unlimited: unlimited,
                    hbt: hbt_,
                    overrideTarget: overrideTarget,
                    smbIsOff: disableSMBs,
                    advancedSettings: overrideArray.first?.advancedSettings ?? false,
                    isfAndCr: overrideArray.first?.isfAndCr ?? false,
                    isf: overrideArray.first?.isf ?? false,
                    cr: overrideArray.first?.cr ?? false,
                    smbIsScheduledOff: overrideArray.first?.smbIsScheduledOff ?? false,
                    start: (overrideArray.first?.start ?? 0) as Decimal,
                    end: (overrideArray.first?.end ?? 0) as Decimal,
                    smbMinutes: (overrideArray.first?.smbMinutes ?? smbMinutes) as Decimal,
                    uamMinutes: (overrideArray.first?.uamMinutes ?? uamMinutes) as Decimal
                )
                storage.save(averages, as: OpenAPS.Monitor.oref2_variables)
                return self.loadFileFromStorage(name: Monitor.oref2_variables)

            } else {
                let averages = Oref2_variables(
                    average_total_data: 0,
                    weightedAverage: 1,
                    past2hoursAverage: 0,
                    date: Date(),
                    isEnabled: temptargetActive,
                    presetActive: isPercentageEnabled,
                    overridePercentage: overridePercentage,
                    useOverride: useOverride,
                    duration: duration,
                    unlimited: unlimited,
                    hbt: hbt_,
                    overrideTarget: overrideTarget,
                    smbIsOff: disableSMBs,
                    advancedSettings: overrideArray.first?.advancedSettings ?? false,
                    isfAndCr: overrideArray.first?.isfAndCr ?? false,
                    isf: overrideArray.first?.isf ?? false,
                    cr: overrideArray.first?.cr ?? false,
                    smbIsScheduledOff: overrideArray.first?.smbIsScheduledOff ?? false,
                    start: (overrideArray.first?.start ?? 0) as Decimal,
                    end: (overrideArray.first?.end ?? 0) as Decimal,
                    smbMinutes: (overrideArray.first?.smbMinutes ?? smbMinutes) as Decimal,
                    uamMinutes: (overrideArray.first?.uamMinutes ?? uamMinutes) as Decimal
                )
                storage.save(averages, as: OpenAPS.Monitor.oref2_variables)
                return self.loadFileFromStorage(name: Monitor.oref2_variables)
            }
        }
    }

    func autosense() -> Future<Autosens?, Never> {
        Future { promise in
            self.processQueue.async {
                debug(.openAPS, "Start autosens")
                let pumpHistory = self.loadFileFromStorage(name: OpenAPS.Monitor.pumpHistory)
                let carbs = self.loadFileFromStorage(name: Monitor.carbHistory)
                let glucose = self.loadFileFromStorage(name: Monitor.glucose)
                let profile = self.loadFileFromStorage(name: Settings.profile)
                let basalProfile = self.loadFileFromStorage(name: Settings.basalProfile)
                let tempTargets = self.loadFileFromStorage(name: Settings.tempTargets)
                let autosensResult = self.autosense(
                    glucose: glucose,
                    pumpHistory: pumpHistory,
                    basalprofile: basalProfile,
                    profile: profile,
                    carbs: carbs,
                    temptargets: tempTargets
                )

                debug(.openAPS, "AUTOSENS: \(autosensResult)")
                if var autosens = Autosens(from: autosensResult) {
                    autosens.timestamp = Date()
                    self.storage.save(autosens, as: Settings.autosense)
                    promise(.success(autosens))
                } else {
                    promise(.success(nil))
                }
            }
        }
    }

    func autotune(categorizeUamAsBasal: Bool = false, tuneInsulinCurve: Bool = false) -> Future<Autotune?, Never> {
        Future { promise in
            self.processQueue.async {
                debug(.openAPS, "Start autotune")
                let pumpHistory = self.loadFileFromStorage(name: OpenAPS.Monitor.pumpHistory)
                let glucose = self.loadFileFromStorage(name: Monitor.glucose)
                let profile = self.loadFileFromStorage(name: Settings.profile)
                let pumpProfile = self.loadFileFromStorage(name: Settings.pumpProfile)
                let carbs = self.loadFileFromStorage(name: Monitor.carbHistory)

                let autotunePreppedGlucose = self.autotunePrepare(
                    pumphistory: pumpHistory,
                    profile: profile,
                    glucose: glucose,
                    pumpprofile: pumpProfile,
                    carbs: carbs,
                    categorizeUamAsBasal: categorizeUamAsBasal,
                    tuneInsulinCurve: tuneInsulinCurve
                )
                debug(.openAPS, "AUTOTUNE PREP: \(autotunePreppedGlucose)")

                let previousAutotune = self.storage.retrieve(Settings.autotune, as: RawJSON.self)

                let autotuneResult = self.autotuneRun(
                    autotunePreparedData: autotunePreppedGlucose,
                    previousAutotuneResult: previousAutotune ?? profile,
                    pumpProfile: pumpProfile
                )

                debug(.openAPS, "AUTOTUNE RESULT: \(autotuneResult)")

                if let autotune = Autotune(from: autotuneResult) {
                    self.storage.save(autotuneResult, as: Settings.autotune)
                    promise(.success(autotune))
                } else {
                    promise(.success(nil))
                }
            }
        }
    }

    func makeProfiles(useAutotune: Bool) -> Future<Autotune?, Never> {
        Future { promise in
            debug(.openAPS, "Start makeProfiles")
            self.processQueue.async {
                var preferences = self.loadFileFromStorage(name: Settings.preferences)
                if preferences.isEmpty {
                    preferences = Preferences().rawJSON
                }
                let pumpSettings = self.loadFileFromStorage(name: Settings.settings)
                let bgTargets = self.loadFileFromStorage(name: Settings.bgTargets)
                let basalProfile = self.loadFileFromStorage(name: Settings.basalProfile)
                let isf = self.loadFileFromStorage(name: Settings.insulinSensitivities)
                let cr = self.loadFileFromStorage(name: Settings.carbRatios)
                let tempTargets = self.loadFileFromStorage(name: Settings.tempTargets)
                let model = self.loadFileFromStorage(name: Settings.model)
                let autotune = useAutotune ? self.loadFileFromStorage(name: Settings.autotune) : .empty
                let freeaps = self.loadFileFromStorage(name: FreeAPS.settings)

                let pumpProfile = self.makeProfile(
                    preferences: preferences,
                    pumpSettings: pumpSettings,
                    bgTargets: bgTargets,
                    basalProfile: basalProfile,
                    isf: isf,
                    carbRatio: cr,
                    tempTargets: tempTargets,
                    model: model,
                    autotune: RawJSON.null,
                    freeaps: freeaps
                )

                let profile = self.makeProfile(
                    preferences: preferences,
                    pumpSettings: pumpSettings,
                    bgTargets: bgTargets,
                    basalProfile: basalProfile,
                    isf: isf,
                    carbRatio: cr,
                    tempTargets: tempTargets,
                    model: model,
                    autotune: autotune.isEmpty ? .null : autotune,
                    freeaps: freeaps
                )

                self.storage.save(pumpProfile, as: Settings.pumpProfile)
                self.storage.save(profile, as: Settings.profile)

                if let tunedProfile = Autotune(from: profile) {
                    promise(.success(tunedProfile))
                    return
                }

                promise(.success(nil))
            }
        }
    }

    // MARK: - Private

    private func iob(pumphistory: JSON, profile: JSON, clock: JSON, autosens: JSON) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.iob))
            worker.evaluate(script: Script(name: Prepare.iob))
            return worker.call(function: Function.generate, with: [
                pumphistory,
                profile,
                clock,
                autosens
            ])
        }
    }

    private func meal(pumphistory: JSON, profile: JSON, basalProfile: JSON, clock: JSON, carbs: JSON, glucose: JSON) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.meal))
            worker.evaluate(script: Script(name: Prepare.meal))
            return worker.call(function: Function.generate, with: [
                pumphistory,
                profile,
                clock,
                glucose,
                basalProfile,
                carbs
            ])
        }
    }

    private func autotunePrepare(
        pumphistory: JSON,
        profile: JSON,
        glucose: JSON,
        pumpprofile: JSON,
        carbs: JSON,
        categorizeUamAsBasal: Bool,
        tuneInsulinCurve: Bool
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.autotunePrep))
            worker.evaluate(script: Script(name: Prepare.autotunePrep))
            return worker.call(function: Function.generate, with: [
                pumphistory,
                profile,
                glucose,
                pumpprofile,
                carbs,
                categorizeUamAsBasal,
                tuneInsulinCurve
            ])
        }
    }

    private func autotuneRun(
        autotunePreparedData: JSON,
        previousAutotuneResult: JSON,
        pumpProfile: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.autotuneCore))
            worker.evaluate(script: Script(name: Prepare.autotuneCore))
            return worker.call(function: Function.generate, with: [
                autotunePreparedData,
                previousAutotuneResult,
                pumpProfile
            ])
        }
    }

    private func determineBasal(
        glucose: JSON,
        currentTemp: JSON,
        iob: JSON,
        profile: JSON,
        autosens: JSON,
        meal: JSON,
        microBolusAllowed: Bool,
        reservoir: JSON,
        pumpHistory: JSON,
        preferences: JSON,
        basalProfile: JSON,
        oref2_variables: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Prepare.determineBasal))
            worker.evaluate(script: Script(name: Bundle.basalSetTemp))
            worker.evaluate(script: Script(name: Bundle.getLastGlucose))
            worker.evaluate(script: Script(name: Bundle.determineBasal))

            if let middleware = self.middlewareScript(name: OpenAPS.Middleware.determineBasal) {
                worker.evaluate(script: middleware)
            }

            return worker.call(
                function: Function.generate,
                with: [
                    iob,
                    currentTemp,
                    glucose,
                    profile,
                    autosens,
                    meal,
                    microBolusAllowed,
                    reservoir,
                    Date(),
                    pumpHistory,
                    preferences,
                    basalProfile,
                    oref2_variables
                ]
            )
        }
    }

    private func autosense(
        glucose: JSON,
        pumpHistory: JSON,
        basalprofile: JSON,
        profile: JSON,
        carbs: JSON,
        temptargets: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.autosens))
            worker.evaluate(script: Script(name: Prepare.autosens))
            return worker.call(
                function: Function.generate,
                with: [
                    glucose,
                    pumpHistory,
                    basalprofile,
                    profile,
                    carbs,
                    temptargets
                ]
            )
        }
    }

    private func exportDefaultPreferences() -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.profile))
            worker.evaluate(script: Script(name: Prepare.profile))
            return worker.call(function: Function.exportDefaults, with: [])
        }
    }

    private func makeProfile(
        preferences: JSON,
        pumpSettings: JSON,
        bgTargets: JSON,
        basalProfile: JSON,
        isf: JSON,
        carbRatio: JSON,
        tempTargets: JSON,
        model: JSON,
        autotune: JSON,
        freeaps: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.profile))
            worker.evaluate(script: Script(name: Prepare.profile))
            return worker.call(
                function: Function.generate,
                with: [
                    pumpSettings,
                    bgTargets,
                    isf,
                    basalProfile,
                    preferences,
                    carbRatio,
                    tempTargets,
                    model,
                    autotune,
                    freeaps
                ]
            )
        }
    }

    private func loadJSON(name: String) -> String {
        try! String(contentsOf: Foundation.Bundle.main.url(forResource: "json/\(name)", withExtension: "json")!)
    }

    private func loadFileFromStorage(name: String) -> RawJSON {
        storage.retrieveRaw(name) ?? OpenAPS.defaults(for: name)
    }

    private func middlewareScript(name: String) -> Script? {
        if let body = storage.retrieveRaw(name) {
            return Script(name: name, body: body)
        }

        if let url = Foundation.Bundle.main.url(forResource: "javascript/\(name)", withExtension: "") {
            return Script(name: name, body: try! String(contentsOf: url))
        }

        return nil
    }

    static func defaults(for file: String) -> RawJSON {
        let prefix = file.hasSuffix(".json") ? "json/defaults" : "javascript"
        guard let url = Foundation.Bundle.main.url(forResource: "\(prefix)/\(file)", withExtension: "") else {
            return ""
        }
        return (try? String(contentsOf: url)) ?? ""
    }
}
