import Foundation

typealias ReachabilityStatus = NetworkReachabilityManager.NetworkReachabilityStatus
typealias Listener = NetworkReachabilityManager.Listener

protocol ReachabilityManager: AnyObject {
    var status: ReachabilityStatus { get }
    var isReachable: Bool { get }
    func startListening(onQueue: DispatchQueue, onUpdatePerforming: @escaping Listener) -> Bool
    func stopListening()
}

extension NetworkReachabilityManager: ReachabilityManager {}

extension ReachabilityStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown:
            return "unknown"
        case .notReachable:
            return "NOT reachable"
        case let .reachable(connectionType):
            return "reachable by " + (connectionType == .cellular ? "Cellular" : "WiFi")
        }
    }
}
