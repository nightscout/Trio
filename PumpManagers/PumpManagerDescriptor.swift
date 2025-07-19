import Foundation

struct PumpManagerDescriptor {
    let type: PumpManagerType
    let name: String
    let description: String
}

let pumpManagerDescriptors: [PumpManagerDescriptor] = [
    PumpManagerDescriptor(type: .diaconG8, name: "Diacon G8", description: "Bluetooth-connected pump from G2E")
]
