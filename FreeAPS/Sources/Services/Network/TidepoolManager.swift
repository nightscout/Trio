import Combine
import Foundation
import LoopKit
import LoopKitUI
import Swinject

protocol TidePoolManager {
    func addTidePoolService(service: Service)
    func getTidePoolServiceUI() -> ServiceUI?
    func getTidePoolPluginHost() -> PluginHost?
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
    @Injected() private var pluginManager: PluginManager!

    private let processQueue = DispatchQueue(label: "BaseNetworkManager.processQueue")
    private var ping: TimeInterval?
    private var tidePoolService: RemoteDataService? {
        didSet {
            if let tidePoolService = tidePoolService {
                rawTidePoolManager = tidePoolService.rawValue
            }
        }
    }

    private var lifetime = Lifetime()

    @PersistedProperty(key: "TidePoolState") var rawTidePoolManager: Service.RawValue?

    init(resolver: Resolver) {
        injectServices(resolver)
        loadTidePoolManager()
        subscribe()
    }

    /// load the TidePool Remote Data Service if available
    fileprivate func loadTidePoolManager() {
        if let rawTidePoolManager = rawTidePoolManager {
            tidePoolService = tidePoolServiceFromRaw(rawTidePoolManager)
            tidePoolService?.serviceDelegate = self
            tidePoolService?.stateDelegate = self
        }
    }

    /// allows to acces to tidePoolService as a simple ServiceUI
    func getTidePoolServiceUI() -> ServiceUI? {
        if let tidePoolService = self.tidePoolService {
            return tidePoolService as! any ServiceUI as ServiceUI
        } else {
            return nil
        }
    }

    func getTidePoolPluginHost() -> PluginHost? {
        self as PluginHost
    }

    func addTidePoolService(service: Service) {
        tidePoolService = service as! any RemoteDataService as RemoteDataService
    }

    /// load the TidePool Remote Data Service from raw storage
    private func tidePoolServiceFromRaw(_ rawValue: [String: Any]) -> RemoteDataService? {
        guard let rawState = rawValue["state"] as? Service.RawStateValue,
              let serviceType = pluginManager.getServiceTypeByIdentifier("TidepoolService")
        else {
            return nil
        }
        if let service = serviceType.init(rawState: rawState) {
            return service as! any RemoteDataService as RemoteDataService
        } else { return nil }
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

extension BaseTidePoolManager: ServiceDelegate {
    var hostIdentifier: String {
        "com.loopkit.Loop" // To check
    }

    var hostVersion: String {
        var semanticVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String

        while semanticVersion.split(separator: ".").count < 3 {
            semanticVersion += ".0"
        }

        semanticVersion += "+\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String)"

        return semanticVersion
    }

    func issueAlert(_: LoopKit.Alert) {}

    func retractAlert(identifier _: LoopKit.Alert.Identifier) {}

    func enactRemoteOverride(name _: String, durationTime _: TimeInterval?, remoteAddress _: String) async throws {}

    func cancelRemoteOverride() async throws {}

    func deliverRemoteCarbs(
        amountInGrams _: Double,
        absorptionTime _: TimeInterval?,
        foodType _: String?,
        startDate _: Date?
    ) async throws {}

    func deliverRemoteBolus(amountInUnits _: Double) async throws {}
}

extension BaseTidePoolManager: StatefulPluggableDelegate {
    func pluginDidUpdateState(_: LoopKit.StatefulPluggable) {}

    func pluginWantsDeletion(_: LoopKit.StatefulPluggable) {}
}

// Service extension for rawValue
extension Service {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        [
            "serviceIdentifier": pluginIdentifier,
            "state": rawState
        ]
    }
}
