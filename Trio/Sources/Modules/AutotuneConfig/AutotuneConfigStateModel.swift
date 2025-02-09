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
        private(set) var units: GlucoseUnits = .mgdL
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
                    return Future { promise in
                        Task.init(priority: .background) {
                            do {
                                _ = try await self.apsManager.makeProfiles()
                                promise(.success(true))

                            } catch {
                                promise(.success(false))
                            }
                        }
                    }
                    .eraseToAnyPublisher()
                }
                .cancellable()
                .store(in: &lifetime)
        }

        func run() {
            Task {
                do {
                    if let result = await self.apsManager.autotune() {
                        autotune = result
                        _ = try await self.apsManager.makeProfiles()
                        lastAutotuneDate = Date()
                    }
                } catch {
                    debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to run Autotune")
                }
            }
        }

        func delete() async {
            provider.deleteAutotune()
            autotune = nil
            do {
                _ = try await apsManager.makeProfiles()
            } catch {
                return
            }
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

extension AutotuneConfig.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
