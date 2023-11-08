import CoreData
import Foundation
import SwiftUI

extension AddCarbs {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var carbsStorage: CarbsStorage!
        @Injected() var apsManager: APSManager!
        @Injected() var settings: SettingsManager!
        @Published var carbs: Decimal = 0
        @Published var date = Date()
        @Published var protein: Decimal = 0
        @Published var fat: Decimal = 0
        @Published var carbsRequired: Decimal?
        @Published var useFPUconversion: Bool = false
        @Published var dish: String = ""
        @Published var selection: Presets?
        @Published var summation: [String] = []
        @Published var maxCarbs: Decimal = 0
        @Published var note: String = ""
        @Published var id_: String = ""
        @Published var summary: String = ""
        @Published var skipBolus: Bool = false

        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

        override func subscribe() {
            carbsRequired = provider.suggestion?.carbsReq
            maxCarbs = settings.settings.maxCarbs
            skipBolus = settingsManager.settings.skipBolusScreenAfterCarbs
            useFPUconversion = settingsManager.settings.useFPUconversion
        }

        func add() {
            guard carbs > 0 || fat > 0 || protein > 0 else {
                showModal(for: nil)
                return
            }
            carbs = min(carbs, maxCarbs)
            id_ = UUID().uuidString

            let carbsToStore = [CarbsEntry(
                collectionID: id_,
                createdAt: date,
                carbs: carbs,
                fat: fat,
                protein: protein,
                note: note,
                enteredBy: CarbsEntry.manual,
                isFPU: false, fpuID: nil
            )]
            carbsStorage.storeCarbs(carbsToStore)

            if skipBolus {
                apsManager.determineBasalSync()
                showModal(for: nil)
            } else if carbs > 0 {
                saveToCoreData(carbsToStore)
                showModal(for: .bolus(waitForSuggestion: true, fetch: true))
            } else {
                hideModal()
            }
        }

        func deletePreset() {
            if selection != nil {
                try? coredataContext.delete(selection!)
                try? coredataContext.save()
                carbs = 0
                fat = 0
                protein = 0
            }
            selection = nil
        }

        func removePresetFromNewMeal() {
            let a = summation.firstIndex(where: { $0 == selection?.dish! })
            if a != nil, summation[a ?? 0] != "" {
                summation.remove(at: a!)
            }
        }

        func addPresetToNewMeal() {
            let test: String = selection?.dish ?? "dontAdd"
            if test != "dontAdd" {
                summation.append(test)
            }
        }

        func addNewPresetToWaitersNotepad(_ dish: String) {
            summation.append(dish)
        }

        func addToSummation() {
            summation.append(selection?.dish ?? "")
        }

        func waitersNotepad() -> String {
            var filteredArray = summation.filter { !$0.isEmpty }

            if carbs == 0, protein == 0, fat == 0 {
                filteredArray = []
            }

            guard filteredArray != [] else {
                return ""
            }
            var carbs_: Decimal = 0.0
            var fat_: Decimal = 0.0
            var protein_: Decimal = 0.0
            var presetArray = [Presets]()

            coredataContext.performAndWait {
                let requestPresets = Presets.fetchRequest() as NSFetchRequest<Presets>
                try? presetArray = coredataContext.fetch(requestPresets)
            }
            var waitersNotepad = [String]()
            var stringValue = ""

            for each in filteredArray {
                let countedSet = NSCountedSet(array: filteredArray)
                let count = countedSet.count(for: each)
                if each != stringValue {
                    waitersNotepad.append("\(count) \(each)")
                }
                stringValue = each

                for sel in presetArray {
                    if sel.dish == each {
                        carbs_ += (sel.carbs)! as Decimal
                        fat_ += (sel.fat)! as Decimal
                        protein_ += (sel.protein)! as Decimal
                        break
                    }
                }
            }
            let extracarbs = carbs - carbs_
            let extraFat = fat - fat_
            let extraProtein = protein - protein_
            var addedString = ""

            if extracarbs > 0, filteredArray.isNotEmpty {
                addedString += "Additional carbs: \(extracarbs) "
            } else if extracarbs < 0 { addedString += "Removed carbs: \(extracarbs) " }

            if extraFat > 0, filteredArray.isNotEmpty {
                addedString += "Additional fat: \(extraFat) "
            } else if extraFat < 0 { addedString += "Removed fat: \(extraFat) " }

            if extraProtein > 0, filteredArray.isNotEmpty {
                addedString += "Additional protein: \(extraProtein) "
            } else if extraProtein < 0 { addedString += "Removed protein: \(extraProtein) " }

            if addedString != "" {
                waitersNotepad.append(addedString)
            }
            var waitersNotepadString = ""

            if waitersNotepad.count == 1 {
                waitersNotepadString = waitersNotepad[0]
            } else if waitersNotepad.count > 1 {
                for each in waitersNotepad {
                    if each != waitersNotepad.last {
                        waitersNotepadString += " " + each + ","
                    } else { waitersNotepadString += " " + each }
                }
            }
            return waitersNotepadString
        }

        func loadEntries(_ editMode: Bool) {
            if editMode {
                coredataContext.perform {
                    var mealToEdit = [Meals]()
                    let requestMeal = Meals.fetchRequest() as NSFetchRequest<Meals>
                    let sortMeal = NSSortDescriptor(key: "createdAt", ascending: false)
                    requestMeal.sortDescriptors = [sortMeal]
                    requestMeal.fetchLimit = 1
                    try? mealToEdit = self.coredataContext.fetch(requestMeal)

                    self.carbs = Decimal(mealToEdit.first?.carbs ?? 0)
                    self.fat = Decimal(mealToEdit.first?.fat ?? 0)
                    self.protein = Decimal(mealToEdit.first?.protein ?? 0)
                    self.note = mealToEdit.first?.note ?? ""
                    self.id_ = mealToEdit.first?.id ?? ""
                }
            }
        }

        func saveToCoreData(_ stored: [CarbsEntry]) {
            let save = Meals(context: coredataContext)
            save.createdAt = Date.now
            save.id = stored.first?.collectionID ?? ""
            save.carbs = Double(stored.first?.carbs ?? 0)
            save.fat = Double(stored.first?.fat ?? 0)
            save.protein = Double(stored.first?.protein ?? 0)
            save.note = stored.first?.note ?? ""
            if coredataContext.hasChanges {
                try? coredataContext.save()
            }
        }
    }
}
