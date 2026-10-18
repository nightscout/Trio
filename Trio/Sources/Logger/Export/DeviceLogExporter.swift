import Foundation
import Swinject

final class DeviceLogExporter: DeviceLogExporting, Injectable {
    @Injected() private var deviceLogStore: DeviceLogStore!
    @Injected() private var deviceDataManager: DeviceDataManager!
    @Injected() private var fetchGlucoseManager: FetchGlucoseManager!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func export(_: DeviceLogExportRequest, into _: URL) async throws {}
}
