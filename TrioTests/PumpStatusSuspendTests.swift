import Foundation
import LoopKit
import Testing
@testable import Trio

@Suite("Pump status suspend from history") struct PumpStatusSuspendTests {
    private let suspendDate = Date(timeIntervalSince1970: 1_800_000_000)

    private func status(suspended: Bool = false, bolusing: Bool = false) -> PumpStatus {
        PumpStatus(
            status: suspended ? .suspended : (bolusing ? .bolusing : .normal),
            bolusing: bolusing,
            suspended: suspended,
            timestamp: suspendDate.addingTimeInterval(600)
        )
    }

    private func event(_ type: PumpEventStored.EventType, at date: Date) -> (type: String, date: Date) {
        (type.rawValue, date)
    }

    @Test("Delivery active since before the last suspend counts as suspended") func noActivePod() {
        let result = status().includingSuspend(
            deliveryActiveSince: .distantPast,
            lastPumpEvent: event(.pumpSuspend, at: suspendDate)
        )
        #expect(result.suspended)
        #expect(result.status == .suspended)
        #expect(result.timestamp == status().timestamp)
    }

    @Test("Delivery active since after the last suspend is not suspended") func newPodWithoutResume() {
        let result = status().includingSuspend(
            deliveryActiveSince: suspendDate.addingTimeInterval(300),
            lastPumpEvent: event(.pumpSuspend, at: suspendDate)
        )
        #expect(result == status())
    }

    @Test("A resume, temp basal or bolus after the suspend is not suspended") func deliveryAfterSuspend() {
        for type in [PumpEventStored.EventType.pumpResume, .tempBasal, .bolus] {
            let result = status().includingSuspend(
                deliveryActiveSince: .distantPast,
                lastPumpEvent: event(type, at: suspendDate.addingTimeInterval(60))
            )
            #expect(result == status())
        }
    }

    @Test("No pump event keeps the pump manager status") func noEvent() {
        #expect(status().includingSuspend(deliveryActiveSince: .distantPast, lastPumpEvent: nil) == status())
    }

    @Test("A suspended pump manager status is kept") func alreadySuspended() {
        let suspended = status(suspended: true)
        #expect(suspended.includingSuspend(deliveryActiveSince: .distantPast, lastPumpEvent: nil) == suspended)
    }

    @Test("Delivery states without delivery map to suspended") func deliveryStateMapping() {
        for state in [PumpStatusStored.DeliveryState.suspended, .inactive, .unknown] {
            #expect(PumpStatus(deliveryState: state, bolusing: false, timestamp: nil).suspended)
        }
        for state in [PumpStatusStored.DeliveryState.active, .suspending, .resuming] {
            #expect(!PumpStatus(deliveryState: state, bolusing: false, timestamp: nil).suspended)
        }
        #expect(PumpStatus(deliveryState: .active, bolusing: true, timestamp: nil).status == .bolusing)
        #expect(PumpStatus(deliveryState: .suspended, bolusing: true, timestamp: nil).status == .suspended)
        #expect(PumpStatusStored.DeliveryState(.active(.distantPast)) == .inactive)
        #expect(PumpStatusStored.DeliveryState(nil) == .unknown)
    }
}
