import Combine
import LoopKit
import SwiftUI

extension AutotuneConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var apsManager: APSManager!
        @Injected() private var storage: FileStorage!
        @Published var useAutotune = false
        @Published var onlyAutotuneBasals = false
        @Published var autotune: Autotune?
        private(set) var units: GlucoseUnits = .mmolL
        @Published var publishedDate = Date()
        @Persisted(key: "lastAutotuneDate") private var lastAutotuneDate = Date() {
            didSet {
                DispatchQueue.main.async {
                    self.publishedDate = self.lastAutotuneDate
                }
            }
        }

        override func subscribe() {
            autotune = provider.autotune
            units = settingsManager.settings.units
            useAutotune = settingsManager.settings.useAutotune
            publishedDate = lastAutotuneDate
            subscribeSetting(\.onlyAutotuneBasals, on: $onlyAutotuneBasals) { onlyAutotuneBasals = $0 }

            $useAutotune
                .removeDuplicates()
                .flatMap { [weak self] use -> AnyPublisher<Bool, Never> in
                    guard let self = self else {
                        return Just(false).eraseToAnyPublisher()
                    }
                    self.settingsManager.settings.useAutotune = use
                    return self.apsManager.makeProfiles()
                }
                .cancellable()
                .store(in: &lifetime)
        }

        func run() {
            provider.runAutotune()
                .receive(on: DispatchQueue.main)
                .flatMap { [weak self] result -> AnyPublisher<Bool, Never> in
                    guard let self = self else {
                        return Just(false).eraseToAnyPublisher()
                    }
                    self.autotune = result
                    return self.apsManager.makeProfiles()
                }
                .sink { [weak self] _ in
                    self?.lastAutotuneDate = Date()
                }.store(in: &lifetime)
        }

        func delete() {
            provider.deleteAutotune()
            autotune = nil
            apsManager.makeProfiles()
                .cancellable()
                .store(in: &lifetime)
        }

        func replace() {
            if let autotunedBasals = autotune {
                let basals = autotunedBasals.basalProfile
                    .map { basal -> BasalProfileEntry in
                        BasalProfileEntry(
                            start: String(basal.start.prefix(5)),
                            minutes: basal.minutes,
                            rate: basal.rate
                        )
                    }
                guard let pump = apsManager.pumpManager else {
                    storage.save(basals, as: OpenAPS.Settings.basalProfile)
                    debug(.service, "Basals have been replaced with Autotuned Basals by user.")
                    return
                }
                let syncValues = basals.map {
                    RepeatingScheduleValue(startTime: TimeInterval($0.minutes * 60), value: Double($0.rate))
                }
                pump.syncBasalRateSchedule(items: syncValues) { result in
                    switch result {
                    case .success:
                        self.storage.save(basals, as: OpenAPS.Settings.basalProfile)
                        debug(.service, "Basals saved to pump!")
                    case .failure:
                        debug(.service, "Basals couldn't be save to pump")
                    }
                }
            }
        }
    }
}
