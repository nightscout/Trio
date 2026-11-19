import CoreData
import Foundation

extension Stat.StateModel {
    /// Reads the current configuration for the settings checks.
    func settingsAnalysisSnapshot() async -> SettingsAnalysis.SettingsSnapshot {
        let preferences = settingsManager.preferences
        let dynamicISF: SettingsAnalysis.DynamicISFMode = !preferences.useNewFormula ? .off
            : preferences.sigmoid ? .sigmoid : .logarithmic

        return SettingsAnalysis.SettingsSnapshot(
            dosingMode: settingsManager.settings.dosingMode,
            dia: settingsManager.pumpSettings.insulinActionCurve,
            maxIOB: preferences.maxIOB,
            smbDeliveryRatio: preferences.smbDeliveryRatio,
            maxDeltaBGThreshold: preferences.maxDeltaBGthreshold,
            dynamicISF: dynamicISF,
            adjustmentFactorSigmoid: preferences.adjustmentFactorSigmoid,
            autosensMax: preferences.autosensMax,
            weightPercentage: preferences.weightPercentage,
            tddHistoryDays: await Self.tddHistoryDays()
        )
    }

    /// Days since the oldest stored TDD entry (including backfilled ones).
    private static func tddHistoryDays(now: Date = Date()) async -> Double? {
        let context = CoreDataStack.shared.newTaskContext()
        return await context.perform {
            let request: NSFetchRequest<TDDStored> = TDDStored.fetchRequest()
            request.predicate = NSPredicate(format: "date != nil")
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
            request.fetchLimit = 1
            guard let oldest = (try? context.fetch(request))?.first?.date else { return nil }
            return now.timeIntervalSince(oldest) / 86400
        }
    }
}
