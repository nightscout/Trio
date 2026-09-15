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
    /// Mirrors `CGMManagerUI.cgmStatusHighlight`; republished on manager change.
    var cgmDisplayState: CurrentValueSubject<CgmDisplayState?, Never> { get }
    /// Mirrors `CGMManagerUI.cgmLifecycleProgress`.
    var cgmProgressHighlight: CurrentValueSubject<LoopKit.DeviceLifecycleProgress?, Never> { get }
}

extension GlucoseSource {
    func sourceInfo() -> [String: Any]? { nil }
}
