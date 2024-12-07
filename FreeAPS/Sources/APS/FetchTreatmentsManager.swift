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
                    // Fetch carbs and temp targets concurrently
                    async let carbs = self.nightscoutManager.fetchCarbs()
                    async let tempTargets = self.nightscoutManager.fetchTempTargets()

                    // Store carbs if available
                    let fetchedCarbs = await carbs
                    if fetchedCarbs.isNotEmpty {
                        await self.carbsStorage.storeCarbs(fetchedCarbs, areFetchedFromRemote: true)
                    }

                    // Store temp targets if available
                    let fetchedTargets = await tempTargets
                    if fetchedTargets.isNotEmpty {
                        // Sort temp targets by date
                        let sortedTargets = fetchedTargets.sorted { lhs, rhs in
                            lhs.createdAt < rhs.createdAt
                        }

                        var lastTempTarget: TempTarget?

                        // Iterate over all temp targets
                        for (index, tempTarget) in sortedTargets.enumerated() {
                            // Skip saving if a Temp Target with the same date already exists
                            guard await !self.tempTargetsStorage.existsTempTarget(with: tempTarget.createdAt) else {
                                debug(
                                    .nightscout,
                                    "Skipping duplicate temp target with date: \(tempTarget.date ?? Date.distantPast)"
                                )
                                continue
                            }

                            // Create a mutable copy of tempTarget
                            var mutableTempTarget = tempTarget

                            // Set enabled to true only for the last temp target
                            mutableTempTarget.enabled = (index == sortedTargets.count - 1)

                            // Save to Core Data
                            await self.tempTargetsStorage.storeTempTarget(tempTarget: mutableTempTarget)

                            // Keep track of the last temp target
                            if index == sortedTargets.count - 1 {
                                lastTempTarget = mutableTempTarget
                            }
                        }

                        // Check if the last Temp Target is a cancel event
                        if let lastTempTarget = lastTempTarget, lastTempTarget.reason == TempTarget.cancel {
                            // Send custom notification to update Adjustments UI
                            Foundation.NotificationCenter.default.post(name: .didUpdateTempTargetConfiguration, object: nil)
                        }

                        // Save the temp targets to JSON so that they get used by oref
                        self.tempTargetsStorage.saveTempTargetsToStorage(sortedTargets)
                    }
                }
            }
            .store(in: &lifetime)
        timer.fire()
        timer.resume()
    }
}
