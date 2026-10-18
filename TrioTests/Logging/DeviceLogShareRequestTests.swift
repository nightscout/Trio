import Foundation
import Testing

@testable import Trio

@Suite("Device Log Share Request Tests") struct DeviceLogShareRequestTests {
    @Test("Request targets the manager over the last 3 days with OSLog and kit files") func requestForManager() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let request = DeviceLogShareRow.request(for: "TestPumpManager", endingAt: now)

        #expect(request.managerIdentifier == "TestPumpManager")
        #expect(request.window.end == now)
        #expect(request.window.duration == 3 * 24 * 60 * 60)
        #expect(request.includeOSLog)
        #expect(request.includeKitFiles)
    }
}
