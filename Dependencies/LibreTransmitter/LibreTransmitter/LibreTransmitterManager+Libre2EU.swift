//
//  LibreTransmitterManager+Libre2EU.swift
//  LibreTransmitter
//
//  Created by LoopKit Authors on 25/04/2022.
//  Copyright © 2022 Mark Wilson. All rights reserved.
//

import Foundation
import LoopKit

extension LibreTransmitterManagerV3 {

    public func libreSensorDidUpdate(with error: LibreError) {

        self.delegateQueue.async {
            self.logDeviceCommunication("Sensor error \(error)", type: .error)
            self.cgmManagerDelegate?.cgmManager(self, hasNew: .error(error))
        }

    }
    

   
    
    public func libreSensorDidUpdate(with bleData: Libre2.LibreBLEResponse, and Device: LibreTransmitterMetadata) {
        self.logger.debug("got sensordata: \(String(describing: bleData))")
        let typeDesc = Device.sensorType().debugDescription

        let now = Date()
        // only once per mins minute
        let mins =  4.5
        if let earlierplus = lastDirectUpdate?.addingTimeInterval(mins * 60), earlierplus >= now {
            logger.debug("last ble update was less than \(mins) minutes ago, aborting loop update")
            self.logDeviceCommunication("Sensor didUpdate (not used) \(bleData)", type: .receive)
            return
        }

        logger.debug("Directly connected to libresensor of type \(typeDesc). Details:  \(Device.description)")
        
        self.logDeviceCommunication("Sensor \(typeDesc) didUpdate \(bleData)", type: .receive)
        

        guard let mapping = UserDefaults.standard.calibrationMapping,
              let calibrationData,
              let sensor = UserDefaults.standard.preSelectedSensor else {
            logger.error("calibrationdata, sensor uid or mapping missing, could not continue")
            
            
            
            self.delegateQueue.async {
                self.cgmManagerDelegate?.cgmManager(self, hasNew: .error(LibreError.noCalibrationData))
            }
            return
        }
        
        

        guard mapping.reverseFooterCRC == calibrationData.isValidForFooterWithReverseCRCs &&
                mapping.uuid == sensor.uuid else {
            logger.error("Calibrationdata was not correct for these bluetooth packets. This is a fatal error, we cannot calibrate without re-pairing")
            self.delegateQueue.async {
                self.cgmManagerDelegate?.cgmManager(self, hasNew: .error(LibreError.noCalibrationData))
            }
            return
        }

        if sensor.maxAge > 0 {
            let minutesLeft = Double(sensor.maxAge - bleData.age)
            NotificationHelper.sendSensorExpireAlertIfNeeded(minutesLeft: minutesLeft)

        }
        

        verifySensorChange(for: sensor.uuid, activatedAt: Date() - TimeInterval(minutes: Double(bleData.age)))
           
        

        let sortedTrends = bleData.trend.sorted { $0.date > $1.date}

        let glucose = LibreGlucose.fromTrendMeasurements(sortedTrends, nativeCalibrationData: calibrationData)

        var newGlucose : [NewGlucoseSample] = glucosesToSamplesFilter(glucose, startDate: getStartDateForFilter())
        // For libre2 bluetooth we do need all trend elements to calculate trendarrow,
        // but we can't report all those trends back to loop
        if let newest = newGlucose.first {
            newGlucose = [newest]
        }

        if newGlucose.isEmpty {
            self.countTimesWithoutData &+= 1
        } else {
            self.latestBackfill = glucose.max { $0.startDate < $1.startDate }
            self.latestPrediction =  self.createBloodSugarPrediction(bleData.trend, calibration: calibrationData)
            self.logger.debug("latestbackfill set to \(self.latestBackfill.debugDescription)")
            self.countTimesWithoutData = 0
        }

        self.setObservables(sensorData: nil, bleData: bleData, metaData: Device)

        self.logger.debug("handleGoodReading returned with \(newGlucose.count) entries")
        self.delegateQueue.async {
            var result: CGMReadingResult
            // If several readings from a valid and running sensor come out empty,
            // we have (with a large degree of confidence) a sensor that has been
            // ripped off the body
            if self.countTimesWithoutData > 1 {
                result = .error(LibreError.noValidSensorData)
            } else {
                result = newGlucose.isEmpty ? .noData : .newData(newGlucose)
            }
            self.cgmManagerDelegate?.cgmManager(self, hasNew: result)
        }

        lastDirectUpdate = Date()

    }
}
