import Combine
import Foundation
import LoopKitUI
import Swinject
import UIKit

protocol TidePoolManager {
    func deleteCarbs(at date: Date, isFPU: Bool?, fpuID: String?, syncID: String)
    func deleteInsulin(at date: Date)
    func uploadStatus()
    func uploadGlucose()
    func uploadStatistics(dailystat: Statistics)
    func uploadPreferences(_ preferences: Preferences)
    func uploadProfileAndSettings(_: Bool)
}

final class BaseTidePoolManager: TidePoolManager, Injectable {
    @Injected() private var broadcaster: Broadcaster!

    private let processQueue = DispatchQueue(label: "BaseNetworkManager.processQueue")
    private var ping: TimeInterval?

    private var lifetime = Lifetime()

    init(resolver: Resolver) {
        injectServices(resolver)
        subscribe()
    }

    private func subscribe() {
        broadcaster.register(PumpHistoryObserver.self, observer: self)
        broadcaster.register(CarbsObserver.self, observer: self)
        broadcaster.register(TempTargetsObserver.self, observer: self)
    }

    func sourceInfo() -> [String: Any]? {
        nil
    }

    func deleteCarbs(at _: Date, isFPU _: Bool?, fpuID _: String?, syncID _: String) {}

    func deleteInsulin(at _: Date) {}

    func uploadStatus() {}

    func uploadGlucose() {}

    func uploadStatistics(dailystat _: Statistics) {}

    func uploadPreferences(_: Preferences) {}

    func uploadProfileAndSettings(_: Bool) {}
}

extension BaseTidePoolManager: PumpHistoryObserver {
    func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {}
}

extension BaseTidePoolManager: CarbsObserver {
    func carbsDidUpdate(_: [CarbsEntry]) {}
}

extension BaseTidePoolManager: TempTargetsObserver {
    func tempTargetsDidUpdate(_: [TempTarget]) {}
}
