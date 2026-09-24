import Combine
import CoreData
import SwiftUI

extension LiveActivitySettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var storage: FileStorage!
        @Injected() var glucoseStorage: GlucoseStorage!

        @Published var units: GlucoseUnits = .mgdL
        @Published var useLiveActivity = false
        @Published var lockScreenView: LockScreenView = .simple
        @Published var smartStackView: LockScreenView = .simple
        @Published var displayGlucoseForecasts = false
        @Published var simpleFontSize: LiveActivityFontSize = .large

        @Published var currentGlucose: Int?
        @Published var currentDelta: Int?
        @Published var currentDirection: BloodGlucose.Direction?

        var glucoseColorScheme: GlucoseColorScheme { settingsManager.settings.glucoseColorScheme }

        override func subscribe() {
            units = settingsManager.settings.units
            subscribeSetting(\.useLiveActivity, on: $useLiveActivity) { useLiveActivity = $0 }
            subscribeSetting(\.lockScreenView, on: $lockScreenView) { lockScreenView = $0 }
            subscribeSetting(\.smartStackView, on: $smartStackView) { smartStackView = $0 }
            subscribeSetting(\.displayGlucoseForecasts, on: $displayGlucoseForecasts) { displayGlucoseForecasts = $0 }
            subscribeSetting(\.liveActivitySimpleFontSize, on: $simpleFontSize) { simpleFontSize = $0 }

            loadCurrentGlucose()
            glucoseStorage.updatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.loadCurrentGlucose() }
                .store(in: &lifetime)
        }

        private func loadCurrentGlucose() {
            Task {
                let context = CoreDataStack.shared.newTaskContext()
                context.name = "loadCurrentGlucose"
                guard let results = try? await CoreDataStack.shared.fetchEntitiesAsync(
                    ofType: GlucoseStored.self,
                    onContext: context,
                    predicate: NSPredicate.predicateForSixHoursAgo,
                    key: "date",
                    ascending: false,
                    fetchLimit: 2
                ) else { return }

                let mapped: (glucose: Int, delta: Int?, direction: BloodGlucose.Direction?)? = await context.perform {
                    guard let readings = results as? [GlucoseStored], let latest = readings.first else { return nil }
                    let previous = readings.dropFirst().first
                    let delta = previous.map { Int(latest.glucose) - Int($0.glucose) }
                    return (Int(latest.glucose), delta, latest.directionEnum)
                }

                await MainActor.run {
                    self.currentGlucose = mapped?.glucose
                    self.currentDelta = mapped?.delta
                    self.currentDirection = mapped?.direction
                }
            }
        }
    }
}

extension LiveActivitySettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
