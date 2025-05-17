import CoreData
import Observation
import SwiftUI

extension AutosensSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!
        @Injected() var determinationStorage: DeterminationStorage!

        var units: GlucoseUnits = .mgdL

        private(set) var autosensISF: Decimal?
        private(set) var autosensRatio: Decimal = 1
        @Published var determinationsFromPersistence: [OrefDetermination] = []

        let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        @Published var autosensMax: Decimal = 1.2
        @Published var autosensMin: Decimal = 0.7
        @Published var rewindResetsAutosens: Bool = true

        var preferences: Preferences {
            settingsManager.preferences
        }

        override func subscribe() {
            units = settingsManager.settings.units

            subscribePreferencesSetting(\.autosensMax, on: $autosensMax) { autosensMax = $0 }
            subscribePreferencesSetting(\.autosensMin, on: $autosensMin) { autosensMin = $0 }
            subscribePreferencesSetting(\.rewindResetsAutosens, on: $rewindResetsAutosens) { rewindResetsAutosens = $0 }

            if let newISF = provider.autosense.newisf {
                autosensISF = newISF
            }

            autosensRatio = provider.autosense.ratio
            setupDeterminationsArray()
        }

        private func setupDeterminationsArray() {
            Task {
                do {
                    let ids = try await determinationStorage.fetchLastDeterminationObjectID(
                        predicate: NSPredicate.enactedDetermination
                    )
                    await updateDeterminationsArray(with: ids)
                } catch {
                    debug(
                        .default,
                        "\(DebuggingIdentifiers.failed) Error fetching determination IDs: \(error)"
                    )
                }
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
                    "Home State: \(#function) \(DebuggingIdentifiers.failed) error while updating the glucose array: \(error)"
                )
            }
        }
    }
}

extension AutosensSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
