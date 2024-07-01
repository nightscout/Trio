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
            .flatMap { _ -> AnyPublisher<([CarbsEntry], [TempTarget]), Never> in
                debug(.nightscout, "FetchTreatmentsManager heartbeat")
                debug(.nightscout, "Start fetching carbs and temptargets")
                return Publishers.CombineLatest(
                    self.nightscoutManager.fetchCarbs(),
                    self.nightscoutManager.fetchTempTargets()
                ).eraseToAnyPublisher()
            }
            .sink { [weak self] carbs, targets in
                guard let self = self else { return }

                Task {
                    let filteredCarbs = carbs.filter { !($0.enteredBy?.contains(CarbsEntry.manual) ?? false) }
                    if filteredCarbs.isNotEmpty {
                        await self.carbsStorage.storeCarbs(filteredCarbs)
                    }
                    let filteredTargets = targets.filter { !($0.enteredBy?.contains(TempTarget.manual) ?? false) }
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
