import Combine
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
                    async let carbs = self.nightscoutManager.fetchCarbs()
                    async let tempTargets = self.nightscoutManager.fetchTempTargets()

                    let filteredCarbs = await carbs.filter { !($0.enteredBy?.contains(CarbsEntry.manual) ?? false) }
                    if filteredCarbs.isNotEmpty {
                        await self.carbsStorage.storeCarbs(filteredCarbs, areFetchedFromRemote: true)
                    }

                    let filteredTargets = await tempTargets.filter { !($0.enteredBy?.contains(TempTarget.manual) ?? false) }
                    if filteredTargets.isNotEmpty {
                        self.tempTargetsStorage.storeTempTargets(filteredTargets)
                    }
                }
            }
            .store(in: &lifetime)
        timer.fire()
        timer.resume()
    }
}
