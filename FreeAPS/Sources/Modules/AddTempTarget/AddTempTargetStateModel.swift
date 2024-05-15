import CoreData
import SwiftUI

extension AddTempTarget {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var storage: TempTargetsStorage!
        @Injected() var apsManager: APSManager!

        let coredataContext = CoreDataStack.shared.backgroundContext

        @Published var low: Decimal = 0
        // @Published var target: Decimal = 0
        @Published var high: Decimal = 0
        @Published var duration: Decimal = 0
        @Published var date = Date()
        @Published var newPresetName = ""
        @Published var presets: [TempTarget] = []
        @Published var percentage = 100.0
        @Published var maxValue: Decimal = 1.2
        @Published var viewPercantage = false
        @Published var hbt: Double = 160
        @Published var saveSettings: Bool = false

        private(set) var units: GlucoseUnits = .mmolL

        override func subscribe() {
            units = settingsManager.settings.units
            presets = storage.presets()
            maxValue = settingsManager.preferences.autosensMax
        }

        func enact() {
            guard duration > 0 else {
                return
            }
            var lowTarget = low

            if viewPercantage {
                lowTarget = Decimal(round(Double(computeTarget())))
                coredataContext.performAndWait {
                    let saveToCoreData = TempTargets(context: self.coredataContext)
                    saveToCoreData.id = UUID().uuidString
                    saveToCoreData.active = true
                    saveToCoreData.hbt = hbt
                    saveToCoreData.date = Date()
                    saveToCoreData.duration = duration as NSDecimalNumber
                    saveToCoreData.startDate = Date()

                    do {
                        try CoreDataStack.shared.backgroundContext.saveContext()
                    } catch {
                        print(error.localizedDescription)
                    }
                }
                saveSettings = true
            } else {
                coredataContext.performAndWait {
                    let saveToCoreData = TempTargets(context: coredataContext)
                    saveToCoreData.active = false
                    saveToCoreData.date = Date()
                    do {
                        try CoreDataStack.shared.backgroundContext.saveContext()
                    } catch {
                        print(error.localizedDescription)
                    }
                }
            }
            var highTarget = lowTarget

            if units == .mmolL, !viewPercantage {
                lowTarget = Decimal(round(Double(lowTarget.asMgdL)))
                highTarget = lowTarget
            }

            let entry = TempTarget(
                name: TempTarget.custom,
                createdAt: date,
                targetTop: highTarget,
                targetBottom: lowTarget,
                duration: duration,
                enteredBy: TempTarget.manual,
                reason: TempTarget.custom
            )
            storage.storeTempTargets([entry])
            showModal(for: nil)
        }

        func cancel() {
            storage.storeTempTargets([TempTarget.cancel(at: Date())])
            showModal(for: nil)

            coredataContext.performAndWait {
                let saveToCoreData = TempTargets(context: self.coredataContext)
                saveToCoreData.active = false
                saveToCoreData.date = Date()
                do {
                    try CoreDataStack.shared.backgroundContext.saveContext()
                } catch {
                    print(error.localizedDescription)
                }

                let setHBT = TempTargetsSlider(context: self.coredataContext)
                setHBT.enabled = false
                setHBT.date = Date()
                do {
                    try CoreDataStack.shared.backgroundContext.saveContext()
                } catch {
                    print(error.localizedDescription)
                }
            }
        }

        func save() {
            guard duration > 0 else {
                return
            }
            var lowTarget = low

            if viewPercantage {
                lowTarget = Decimal(round(Double(computeTarget())))
                saveSettings = true
            }
            var highTarget = lowTarget

            if units == .mmolL, !viewPercantage {
                lowTarget = Decimal(round(Double(lowTarget.asMgdL)))
                highTarget = lowTarget
            }

            let entry = TempTarget(
                name: newPresetName.isEmpty ? TempTarget.custom : newPresetName,
                createdAt: Date(),
                targetTop: highTarget,
                targetBottom: lowTarget,
                duration: duration,
                enteredBy: TempTarget.manual,
                reason: newPresetName.isEmpty ? TempTarget.custom : newPresetName
            )
            presets.append(entry)
            storage.storePresets(presets)

            if viewPercantage {
                let id = entry.id

                coredataContext.performAndWait {
                    let saveToCoreData = TempTargetsSlider(context: self.coredataContext)
                    saveToCoreData.id = id
                    saveToCoreData.isPreset = true
                    saveToCoreData.enabled = true
                    saveToCoreData.hbt = hbt
                    saveToCoreData.date = Date()
                    saveToCoreData.duration = duration as NSDecimalNumber
                    do {
                        try CoreDataStack.shared.backgroundContext.saveContext()
                    } catch {
                        print(error.localizedDescription)
                    }
                }
            }
        }

        func enactPreset(id: String) {
            if var preset = presets.first(where: { $0.id == id }) {
                preset.createdAt = Date()
                storage.storeTempTargets([preset])
                showModal(for: nil)

                coredataContext.performAndWait {
                    var tempTargetsArray = [TempTargetsSlider]()
                    let requestTempTargets = TempTargetsSlider.fetchRequest() as NSFetchRequest<TempTargetsSlider>
                    let sortTT = NSSortDescriptor(key: "date", ascending: false)
                    requestTempTargets.sortDescriptors = [sortTT]
                    try? tempTargetsArray = coredataContext.fetch(requestTempTargets)

                    let whichID = tempTargetsArray.first(where: { $0.id == id })

                    if whichID != nil {
                        let saveToCoreData = TempTargets(context: self.coredataContext)
                        saveToCoreData.active = true
                        saveToCoreData.date = Date()
                        saveToCoreData.hbt = whichID?.hbt ?? 160
                        // saveToCoreData.id = id
                        saveToCoreData.startDate = Date()
                        saveToCoreData.duration = whichID?.duration ?? 0

                        do {
                            try CoreDataStack.shared.backgroundContext.saveContext()
                        } catch {
                            print(error.localizedDescription)
                        }
                    } else {
                        let saveToCoreData = TempTargets(context: self.coredataContext)
                        saveToCoreData.active = false
                        saveToCoreData.date = Date()
                        do {
                            try CoreDataStack.shared.backgroundContext.saveContext()
                        } catch {
                            print(error.localizedDescription)
                        }
                    }
                }
            }
        }

        func removePreset(id: String) {
            presets = presets.filter { $0.id != id }
            storage.storePresets(presets)
        }

        func computeTarget() -> Decimal {
            var ratio = Decimal(percentage / 100)
            let c = Decimal(hbt - 100)
            var target = (c / ratio) - c + 100

            if c * (c + target - 100) <= 0 {
                ratio = maxValue
                target = (c / ratio) - c + 100
            }
            return Decimal(Double(target))
        }
    }
}
