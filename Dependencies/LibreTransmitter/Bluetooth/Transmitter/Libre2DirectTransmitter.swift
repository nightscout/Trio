//
//  Libre2DirectTransmitter.swift

import CoreBluetooth
import Foundation
import os.log
import UIKit

class Libre2DirectTransmitter: LibreTransmitterProxyProtocol {

    fileprivate lazy var logger = Logger(forType: Self.self)

    func reset() {
        rxBuffer.resetAllBytes()
    }

    class var manufacturerer: String {
        "Abbott"
    }

    class var smallImage: UIImage? {
        UIImage(named: "libresensor", in: Bundle.current, compatibleWith: nil)
    }

    class var shortTransmitterName: String {
        "libre2"
    }

    class var requiresDelayedReconnect: Bool {
        false
    }

    private let expectedBufferSize = 46
    static var requiresSetup = true
    static var requiresPhoneNFC: Bool = true

    static var writeCharacteristic: UUIDContainer? = "F001"// 0000f001-0000-1000-8000-00805f9b34fb"
    static var notifyCharacteristic: UUIDContainer? = "F002"// "0000f002-0000-1000-8000-00805f9b34fb"
    // static var serviceUUID: [UUIDContainer] = ["0000fde3-0000-1000-8000-00805f9b34fb"]
    static var serviceUUID: [UUIDContainer] = ["FDE3"]

    weak var delegate: LibreTransmitterDelegate?

    private var rxBuffer = Data()
    private var sensorData: SensorData?
    private var metadata: LibreTransmitterMetadata?

    class func canSupportPeripheral(_ peripheral: PeripheralProtocol) -> Bool {
        peripheral.name?.lowercased().starts(with: "abbott") ?? false
    }

    class func getDeviceDetailsFromAdvertisement(advertisementData: [String: Any]?) -> String? {
        nil
    }

    required init(delegate: LibreTransmitterDelegate, advertisementData: [String: Any]?) {
        // advertisementData is unknown for the miaomiao
        self.delegate = delegate
    }

    func requestData(writeCharacteristics: CBCharacteristic, peripheral: CBPeripheral) {
        // because of timing issues, we cannot use this method on libre2 eu sensors
    }

    func updateValueForNotifyCharacteristics(_ value: Data, peripheral: CBPeripheral, writeCharacteristic: CBCharacteristic?) {
        rxBuffer.append(value)

        logger.debug("libre2 direct Appended value with length  \(String(describing: value.count)), buffer length is: \(String(describing: self.rxBuffer.count))")
        
        delegate?.libreDeviceLogMessage(payload: "libre2direct received value: \(value.toDebugString())", type: .receive)

        if rxBuffer.count == expectedBufferSize {
            handleCompleteMessage()
        }

    }

    func didDiscoverWriteCharacteristics(_ peripheral: CBPeripheral, writeCharacteristics: CBCharacteristic) {

        guard let unlock = unlock() else {
            logger.debug("Cannot unlock sensor, aborting")
            return
        }

        logger.debug("Writing streaming unlock code to peripheral: \(unlock.hexEncodedString())")
        
        delegate?.libreDeviceLogMessage(payload: "Writing streaming unlock code to peripheral: \(unlock.hexEncodedString())", type: .send)
        peripheral.writeValue(unlock, for: writeCharacteristics, type: .withResponse)

    }

    func didDiscoverNotificationCharacteristic(_ peripheral: CBPeripheral, notifyCharacteristic: CBCharacteristic) {

        logger.debug("libre2: saving notifyCharacteristic")
        // peripheral.setNotifyValue(true, for: notifyCharacteristic)
        logger.debug("libre2 setting notify while discovering : \(String(describing: notifyCharacteristic.debugDescription))")
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
    }

    private func unlock() -> Data? {

        guard var sensor = UserDefaults.standard.preSelectedSensor else {
            logger.debug("impossible to unlock sensor")
            return nil
        }

        sensor.unlockCount +=  1

        UserDefaults.standard.preSelectedSensor = sensor

        let unlockPayload = Libre2.streamingUnlockPayload(sensorUID: sensor.uuid, info: sensor.patchInfo, enableTime: 42, unlockCount: UInt16(sensor.unlockCount))
        return Data(unlockPayload)

    }

    // previously captured trend values, limit to the last 20-ish minutes
    // we have some leniency here by having up to 30 data elements
    private var bufferedTrends =  LimitedQueue<Measurement>(limit: 30)
    private var lastSensorUUID : [UInt8]?
    func handleCompleteMessage() {
        guard rxBuffer.count >= expectedBufferSize else {
            logger.debug("libre2 handle complete message with incorrect buffersize")
            reset()
            return
        }

        guard let sensor = UserDefaults.standard.preSelectedSensor else {
            logger.debug("libre2 handle complete message without sensorinfo present")
            reset()
            return
        }

        do {
            let decryptedBLE = Data(try Libre2.decryptBLE(id: [UInt8](sensor.uuid), data: [UInt8](rxBuffer)))
            var sensorUpdate = Libre2.parseBLEData(decryptedBLE)
 

            guard sensorUpdate.crcVerified else {
                delegate?.libreSensorDidUpdate(with: .checksumValidationError)
                return
            }
            

            metadata = LibreTransmitterMetadata(hardware: nil, firmware: nil, battery: 100,
                                                name: Self.shortTransmitterName,
                                                macAddress: nil,
                                                patchInfo: sensor.patchInfo,
                                                uid: [UInt8](sensor.uuid))

            // When end user has changed sensor we cannot trust the current(new) calibrationdata
            // to apply for both old and new sensor.
            // Since we don't support multiple sets of calibration datas we chooce to remove
            // all buffered calibration data
            if let currentSensorUUID = metadata?.uid {
                if let lastSensorUUID,
                    lastSensorUUID != currentSensorUUID {
                    bufferedTrends.removeAll()

                }
                lastSensorUUID = currentSensorUUID
            }

            // todo: reset when sensor changes, but we currently don't need this
            // due to requirement of deleting cgmmanager when changing sensors
            if let latestGlucose = sensorUpdate.trend.last,
               let oldestGlucose = sensorUpdate.trend.first {
                // ensures captured trends are recent enough
                // but also older than the trends sent by sensor this time around
                let latestGlucoseDate = latestGlucose.date - TimeInterval(minutes: 20)
                let oldestGlucoseDate = oldestGlucose.date

                let filtered = bufferedTrends.array.filter {
                    $0.date > latestGlucoseDate &&
                    $0.date < oldestGlucoseDate
                }.removingDuplicates(byKey: { $0.idValue})

                // Could refactor this to be more performant, but decided not to
                // This is more explicit and easier to grasp than doing above and below
                // in one operation
                for trend in sensorUpdate.trend {
                    if !bufferedTrends.array.contains(where: { $0.date > trend.date}) {
                        bufferedTrends.enqueue(trend)
                    }

                }

                logger.debug("sensor updated with trends: \((sensorUpdate.trend.count)): \(sensorUpdate.trend)")

                if !filtered.isEmpty {
                    logger.debug("Adding previously captured trends \((filtered.count)): \(filtered)")
                    sensorUpdate.trend += filtered
                }
            }

            delegate?.libreSensorDidUpdate(with: sensorUpdate, and: metadata!)

            print("libre2 got sensorupdate: \(String(describing: sensorUpdate))")

        } catch {

        }

        reset()

    }

}
