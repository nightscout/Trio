import Combine
import CoreData
import Foundation
import SwiftDate
import Swinject

protocol FetchTreatmentsManager {}

final class BaseFetchTreatmentsManager: FetchTreatmentsManager, Injectable {
    private let processQueue = DispatchQueue(label: "BaseFetchTreatmentsManager.processQueue")
    @Injected() var nightscoutManager: NightscoutManager!
    @Injected() var tempTargetsStorage: TempTargetsStorage!
    @Injected() var carbsStorage: CarbsStorage!

    private var lifetime = Lifetime()
    private let timer = DispatchTimer(timeInterval: 1.minutes.timeInterval)
    private var backgroundContext = CoreDataStack.shared.newTaskContext()

    init(resolver: Resolver) {
        injectServices(resolver)
        subscribe()
    }

    private func subscribe() {
        timer.publisher
            .receive(on: processQueue)
            .sink { [weak self] _ in
                guard let self = self else { return }
                debug(.nightscout, "FetchTreatmentsManager heartbeat")
                debug(.nightscout, "Start fetching carbs and temptargets")

                Task {
                    do {
                        // Fetch carbs and temp targets concurrently
                        async let carbs = self.nightscoutManager.fetchCarbs()
                        async let tempTargets = self.nightscoutManager.fetchTempTargets()

                        // Filter and store if not from "Trio"
                        let filteredCarbs = await carbs.filter { $0.enteredBy != CarbsEntry.local }
                        if filteredCarbs.isNotEmpty {
                            try await self.carbsStorage.storeCarbs(filteredCarbs, areFetchedFromRemote: true)
                        }

                        // Filter and store if not from Trio
                        let filteredTargets = await tempTargets.filter { $0.enteredBy != TempTarget.local }
                        if filteredTargets.isNotEmpty {
                            // Sort temp targets by creation date
                            let sortedTargets = filteredTargets.sorted { $0.createdAt < $1.createdAt }

                            // Iterate and store each temp target
                            for (index, tempTarget) in sortedTargets.enumerated() {
                                // Skip saving if a Temp Target with the same date already exists or it's a cancel target
                                guard await !self.tempTargetsStorage.existsTempTarget(with: tempTarget.createdAt),
                                      tempTarget.reason != TempTarget.cancel
                                else {
                                    debug(
                                        .nightscout,
                                        "Skipping temp target with date: \(tempTarget.date ?? Date.distantPast)"
                                    )
                                    continue
                                }

                                // Create a mutable copy and set enabled for the last temp target
                                var mutableTempTarget = tempTarget
                                mutableTempTarget.enabled = (index == sortedTargets.count - 1)

                                // Save to Core Data
                                try await self.tempTargetsStorage.storeTempTarget(tempTarget: mutableTempTarget)
                            }

                            // Save the temp targets to JSON so that they get used by oref
                            self.tempTargetsStorage.saveTempTargetsToStorage(sortedTargets)

                            // Update Adjustments View
                            Foundation.NotificationCenter.default.post(name: .didUpdateTempTargetConfiguration, object: nil)
                        }
                    } catch {
                        debug(.default, "\(DebuggingIdentifiers.failed) error in \(#file) \(#function): \(error)")
                    }
                }
            }
            .store(in: &lifetime)
        timer.fire()
        timer.resume()
    }
}
