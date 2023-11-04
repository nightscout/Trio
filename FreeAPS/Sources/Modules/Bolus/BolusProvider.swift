import CoreData

extension Bolus {
    final class Provider: BaseProvider, BolusProvider {
        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

        var suggestion: Suggestion? {
            storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
        }

        func pumpSettings() -> PumpSettings {
            storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
                ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
                ?? PumpSettings(insulinActionCurve: 6, maxBolus: 10, maxBasal: 2)
        }

        func getProfile() -> [BasalProfileEntry] {
            storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
                ?? [BasalProfileEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.basalProfile))
                ?? []
        }

        func fetchGlucose() -> [Readings] {
            var fetchGlucose = [Readings]()
            coredataContext.performAndWait {
                let requestReadings = Readings.fetchRequest() as NSFetchRequest<Readings>
                let sort = NSSortDescriptor(key: "date", ascending: true)
                requestReadings.sortDescriptors = [sort]
                requestReadings.predicate = NSPredicate(
                    format: "glucose > 0 AND date > %@",
                    Date().addingTimeInterval(-1.hours.timeInterval) as NSDate
                )
                try? fetchGlucose = self.coredataContext.fetch(requestReadings)
            }
            return fetchGlucose
        }
    }
}
