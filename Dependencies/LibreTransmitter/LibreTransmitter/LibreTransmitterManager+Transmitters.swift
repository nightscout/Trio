//
//  LibreTransmitterManager+Transmitters.swift
//  LibreTransmitter
//
//  Created by LoopKit Authors on 25/04/2022.
//  Copyright © 2022 Mark Wilson. All rights reserved.
//

import Foundation
import LoopKit

// MARK: - Bluetooth transmitter data
extension LibreTransmitterManagerV3 {

    public func noLibreTransmitterSelected() {
        NotificationHelper.sendNoTransmitterSelectedNotification()
    }

    public func libreTransmitterDidUpdate(with sensorData: SensorData, and Device: LibreTransmitterMetadata) {

        self.logger.debug("got sensordata: \(String(describing: sensorData)), bytescount: \( sensorData.bytes.count), bytes: \(sensorData.bytes)")
        var sensorData = sensorData

        NotificationHelper.sendLowBatteryNotificationIfNeeded(device: Device)
        self.setObservables(sensorData: nil, bleData: nil, metaData: Device)

         if !sensorData.isLikelyLibre1FRAM {
            if let patchInfo = sensorData.patchInfo {
                let sensorType = SensorType(patchInfo: patchInfo)
                let needsDecryption = [SensorType.libre2, .libreUS14day].contains(sensorType)
                if needsDecryption, let uid = Device.uid {
                    sensorData.decrypt(patchInfo: patchInfo, uid: uid)
                }
            } else {
                logger.debug("Sensor type was incorrect, and no decryption of sensor was possible")
                self.cgmManagerDelegate?.cgmManager(self, hasNew: .error(LibreError.encryptedSensor))
                return
            }
        }

        let typeDesc = Device.sensorType().debugDescription

        logger.debug("Transmitter connected to libresensor of type \(typeDesc). Details:  \(Device.description)")

        tryPersistSensorData(with: sensorData)

        NotificationHelper.sendInvalidSensorNotificationIfNeeded(sensorData: sensorData)
        NotificationHelper.sendInvalidChecksumIfDeveloper(sensorData)

        guard sensorData.hasValidCRCs else {
            self.delegateQueue.async {
                self.cgmManagerDelegate?.cgmManager(self, hasNew: .error(LibreError.checksumValidationError))
            }

            logger.debug("did not get sensordata with valid crcs")
            return
        }

        NotificationHelper.sendSensorExpireAlertIfNeeded(sensorData: sensorData)

        guard sensorData.state == .ready || sensorData.state == .starting else {
            logger.debug("got sensordata with valid crcs, but sensor is either expired or failed")
            self.delegateQueue.async {
                self.cgmManagerDelegate?.cgmManager(self, hasNew: .error(LibreError.expiredSensor))
            }
            return
        }

        logger.debug("got sensordata with valid crcs, sensor was ready")
        // self.lastValidSensorData = sensorData

        
        verifySensorChange(for: sensorData.uuid, activatedAt: Date() - TimeInterval(minutes: Double(sensorData.minutesSinceStart)))
        
        

        self.handleGoodReading(data: sensorData) { [weak self] error, glucoseArrayWithPrediction in
            guard let self else {
                print(" handleGoodReading could not lock on self, aborting")
                return
            }
            if let error {
                self.logger.error(" handleGoodReading returned with error: \(error.errorDescription)")
                self.delegateQueue.async {
                    self.cgmManagerDelegate?.cgmManager(self, hasNew: .error(error))
                }
                return
            }

            guard let glucose = glucoseArrayWithPrediction?.trends else {
                self.logger.debug("handleGoodReading returned with no data")
                self.delegateQueue.async {
                    self.cgmManagerDelegate?.cgmManager(self, hasNew: .noData)
                }
                return
            }

            let prediction = glucoseArrayWithPrediction?.prediction

            var newGlucoses : [NewGlucoseSample] = []
            
            // Since trends have a spacing of 1 minute between them, we use that to calculate trend arrows
            var trends = self.glucosesToSamplesFilter(glucose, startDate: self.getStartDateForFilter())
            
            // But since Loop only supports 1 glucose reading
            // every 5 minutes, we remove all readings except the newest
            if let newest = trends.first {
                trends = [newest]
            }
            
            // Historical readings have a spacing of 15 minutes between them,
            // trend arrow calculation doesn't make that much sense
            if let historical = glucoseArrayWithPrediction?.historical {
                let historical2 = self.glucosesToSamplesFilter(historical, startDate: self.getStartDateForFilter(), calculateTrends: false)
                if !historical.isEmpty {
                    newGlucoses = historical2
                }
                
            }
            newGlucoses += trends

            if newGlucoses.isEmpty {
                self.countTimesWithoutData &+= 1
            } else {
                self.latestBackfill = glucose.max { $0.startDate < $1.startDate }
                self.logger.debug("latestbackfill set to \(self.latestBackfill.debugDescription)")
                self.countTimesWithoutData = 0
            }

            self.latestPrediction = prediction?.first

            // must be inside this handler as setobservables "depend" on latestbackfill
            self.setObservables(sensorData: sensorData, bleData: nil, metaData: nil)

            self.logger.debug("handleGoodReading returned with \(newGlucoses.count) entries")
            self.delegateQueue.async {
                var result: CGMReadingResult
                // If several readings from a valid and running sensor come out empty,
                // we have (with a large degree of confidence) a sensor that has been
                // ripped off the body
                if self.countTimesWithoutData > 1 {
                    result = .error(LibreError.noValidSensorData)
                } else {
                    result = newGlucoses.isEmpty ? .noData : .newData(newGlucoses)
                }
                self.cgmManagerDelegate?.cgmManager(self, hasNew: result)
            }
        }

    }
    private func readingToGlucose(_ data: SensorData, calibration: SensorData.CalibrationInfo) -> GlucoseArrayWithPrediction {

        var entries: [LibreGlucose] = []
        var historical: [LibreGlucose] = []
        var prediction: [LibreGlucose] = []

        let trends = data.trendMeasurements()

        if let temp = createBloodSugarPrediction(trends, calibration: calibration) {
            prediction.append(temp)
        }

        entries = LibreGlucose.fromTrendMeasurements(trends, nativeCalibrationData: calibration)

        if UserDefaults.standard.mmBackfillFromHistory {
            let history = data.historyMeasurements()
            historical += LibreGlucose.fromHistoryMeasurements(history, nativeCalibrationData: calibration)
        }

        return (trends: entries, historical: historical, prediction: prediction)
    }

    public func handleGoodReading(data: SensorData?, _ callback: @escaping (LibreError?, GlucoseArrayWithPrediction?) -> Void) {
        // only care about the once per minute readings here, historical data will not be considered

        guard let data else {
            callback(.noSensorData, nil)
            return
        }
        
        if let calibrationData {
            logger.debug("calibrationdata loaded")

            if calibrationData.isValidForFooterWithReverseCRCs == data.footerCrc.byteSwapped {
                logger.debug("calibrationdata correct for this sensor, returning last values")

                callback(nil, readingToGlucose(data, calibration: calibrationData))
                return
            } else {
                logger.debug(
                """
                 calibrationdata incorrect for this sensor, calibrationdata.isValidForFooterWithReverseCRCs:
                \(calibrationData.isValidForFooterWithReverseCRCs),
                data.footerCrc.byteSwapped: \(data.footerCrc.byteSwapped)
                """)

            }
        } else {
            logger.debug("calibrationdata was nil")
        }

        calibrateSensor(sensordata: data) { [weak self] calibrationparams  in
            do {
                try KeychainManager.standard.setLibreNativeCalibrationData(calibrationparams)
            } catch {
                NotificationHelper.sendCalibrationNotification(.invalidCalibrationData)
                callback(.invalidCalibrationData, nil)
                return
            }
            // here we assume success, data is not changed,
            // and we trust that the remote endpoint returns correct data for the sensor

            NotificationHelper.sendCalibrationNotification(.success)
            callback(nil, self?.readingToGlucose(data, calibration: calibrationparams))
        }
    }

    // will be called on utility queue
    public func libreDeviceStateChanged(_ state: BluetoothmanagerState) {
        DispatchQueue.main.async {
            self.transmitterInfoObservable.connectionState = self.proxy?.connectionStateString ?? "n/a"
            self.transmitterInfoObservable.transmitterType = self.proxy?.shortTransmitterName ?? "Unknown"
        }
        logDeviceCommunication("Sensor/Transmitter Device change state to: \(state.rawValue))", type: .connection)
        
        
        if case .Connected = state {
            lastConnected = Date()
        }
        
        return
    }
    
    public func libreDeviceLogMessage(payload: String, type: LoopKit.DeviceLogEntryType) {
        logDeviceCommunication(payload, type: type)
    }

    // will be called on utility queue
    public func libreDeviceReceivedMessage(_ txFlags: UInt8, payloadData: Data) {
        
        guard let packet = MiaoMiaoResponseState(rawValue: txFlags) else {
            // Incomplete package?
            // this would only happen if delegate is called manually with an unknown txFlags value
            // this was the case for readouts that were not yet complete
            logger.debug("Incomplete package or unknown response state")
            return
        }

        switch packet {
        case .newSensor:
            //we can't be sure of the activation datetime for the new sensor here
            logger.debug("New libresensor detected")
            NotificationHelper.sendSensorChangeNotificationIfNeeded()
        case .noSensor:
            logger.debug("No libresensor detected")
            NotificationHelper.sendSensorNotDetectedNotificationIfNeeded(noSensor: true)
        default:
            // we don't care about the rest!
            break
        }

        return
    }

    func tryPersistSensorData(with sensorData: SensorData) {
        guard UserDefaults.standard.shouldPersistSensorData else {
            return
        }

        // yeah, we really really need to persist any changes right away
        var data = UserDefaults.standard.queuedSensorData ?? LimitedQueue<SensorData>()
        data.enqueue(sensorData)
        UserDefaults.standard.queuedSensorData = data
    }
}
