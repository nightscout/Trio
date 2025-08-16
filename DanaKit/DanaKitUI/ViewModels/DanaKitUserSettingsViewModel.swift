import Foundation
import LoopKit

class DanaKitUserSettingsViewModel: ObservableObject {
    @Published var storingUseroption = false
    @Published var lowReservoirRate: UInt8
    @Published var isTimeDisplay24H: Bool
    @Published var isButtonScrollOnOff: Bool
    @Published var beepAndAlarm: BeepAlarmType
    @Published var lcdOnTimeInSec: UInt8
    @Published var backlightOnTimeInSec: UInt8
    @Published var refillAmount: UInt16

    private let pumpManager: DanaKitPumpManager?

    init(_ pumpManager: DanaKitPumpManager?) {
        self.pumpManager = pumpManager

        lowReservoirRate = self.pumpManager?.state.lowReservoirRate ?? 0
        isTimeDisplay24H = self.pumpManager?.state.isTimeDisplay24H ?? false
        isButtonScrollOnOff = self.pumpManager?.state.isButtonScrollOnOff ?? false
        beepAndAlarm = self.pumpManager?.state.beepAndAlarm ?? .sound
        lcdOnTimeInSec = self.pumpManager?.state.lcdOnTimeInSec ?? 0
        backlightOnTimeInSec = self.pumpManager?.state.backlightOnTimInSec ?? 0
        refillAmount = self.pumpManager?.state.refillAmount ?? 0
    }

    func storeUserOption() {
        guard let pumpManager = self.pumpManager else {
            return
        }

        storingUseroption = true
        let model = PacketGeneralSetUserOption(
            isTimeDisplay24H: isTimeDisplay24H,
            isButtonScrollOnOff: isButtonScrollOnOff,
            beepAndAlarm: beepAndAlarm.rawValue,
            lcdOnTimeInSec: lcdOnTimeInSec,
            backlightOnTimeInSec: backlightOnTimeInSec,
            selectedLanguage: pumpManager.state.selectedLanguage,
            units: pumpManager.state.units,
            shutdownHour: pumpManager.state.shutdownHour,
            lowReservoirRate: lowReservoirRate,
            cannulaVolume: pumpManager.state.cannulaVolume,
            refillAmount: refillAmount,
            targetBg: pumpManager.state.targetBg
        )

        pumpManager.setUserSettings(data: model, completion: { _ in
            DispatchQueue.main.async {
                self.storingUseroption = false
            }
        })
    }
}
