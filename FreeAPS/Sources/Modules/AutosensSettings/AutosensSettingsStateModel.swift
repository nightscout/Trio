import CoreData
import Observation
import SwiftUI

extension AutosensSettings {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var settings: SettingsManager!
        @ObservationIgnored @Injected() var storage: FileStorage!
        @ObservationIgnored @Injected() var determinationStorage: DeterminationStorage!

        var units: GlucoseUnits = .mgdL

        private(set) var autosensISF: Decimal?
        private(set) var autosensRatio: Decimal = 0
        var determinationsFromPersistence: [OrefDetermination] = []

        let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        var autosensMax: Decimal = 1.2
        var autosensMin: Decimal = 0.7
        var rewindResetsAutosens: Bool = true

        var preferences: Preferences {
            settingsManager.preferences
        }

        override func subscribe() {
            units = settingsManager.settings.units

            autosensMax = settings.preferences.autosensMax
            autosensMin = settings.preferences.autosensMin
            rewindResetsAutosens = settings.preferences.rewindResetsAutosens

            if let newISF = provider.autosense.newisf {
                autosensISF = newISF
            }

            autosensRatio = provider.autosense.ratio
            setupDeterminationsArray()
        }

        var isSettingUnchanged: Bool {
            preferences.autosensMax == autosensMax &&
                preferences.autosensMin == autosensMin &&
                preferences.rewindResetsAutosens == rewindResetsAutosens
        }

        func saveIfChanged() {
            if !isSettingUnchanged {
                var newSettings = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self) ?? Preferences()

                newSettings.autosensMax = autosensMax
                newSettings.autosensMin = autosensMin
                newSettings.rewindResetsAutosens = rewindResetsAutosens

                newSettings.timestamp = Date()
                storage.save(newSettings, as: OpenAPS.Settings.preferences)
            }
        }

        private func setupDeterminationsArray() {
            Task {
                let ids = await determinationStorage.fetchLastDeterminationObjectID(
                    predicate: NSPredicate.enactedDetermination
                )
                await updateDeterminationsArray(with: ids)
            }
        }

        @MainActor private func updateDeterminationsArray(with IDs: [NSManagedObjectID]) {
            do {
                let objects = try IDs.compactMap { id in
                    try viewContext.existingObject(with: id) as? OrefDetermination
                }
                determinationsFromPersistence = objects

            } catch {
                debugPrint(
                    "Home State: \(#function) \(DebuggingIdentifiers.failed) error while updating the glucose array: \(error.localizedDescription)"
                )
            }
        }
    }
}

extension AutosensSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
    }
}
