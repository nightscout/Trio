import Foundation

struct PumpManagerFactory {
    static func createManager(for type: PumpManagerType) -> PumpManager {
        switch type {
        case .diaconG8:
            return DiaconPumpManager()
        }
    }
}
