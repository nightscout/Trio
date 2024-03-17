import Combine
import LoopKit
import LoopKitUI

protocol SourceInfoProvider {
    func sourceInfo() -> [String: Any]?
}

protocol GlucoseSource: SourceInfoProvider {
    func fetch(_ heartbeat: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never>
    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never>
    var glucoseManager: FetchGlucoseManager? { get set }
    var cgmManager: CGMManagerUI? { get set }
}

extension GlucoseSource {
    func sourceInfo() -> [String: Any]? { nil }
}
