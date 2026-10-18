import Foundation

struct DeviceLogExportRequest {
    var window: DateInterval
    var managerIdentifier: String?
    var includeOSLog: Bool
    var includeKitFiles: Bool
}

protocol DeviceLogExporting {
    func export(_ request: DeviceLogExportRequest, into directory: URL) async throws
}
