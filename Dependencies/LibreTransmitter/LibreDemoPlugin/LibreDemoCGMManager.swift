//
//  LibreDemoCGMManager.swift
//  LibreTransmitter
//
//  Created by Pete Schwamb on 6/21/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import LibreTransmitter
import LibreTransmitterUI
import LoopKit
import LoopKitUI
import HealthKit
import os.log
import LoopTestingKit

class LibreDemoCGMManager: LibreTransmitterManagerV3 {
    var timer: Timer?

    private let log = OSLog(category: "LibreDemoCGMManager")


    override var localizedTitle: String { "Libre Demo" }

    public var managerIdentifier: String {
        "LibreDemoCGMManager"
    }

    public override var pairingService: SensorPairingProtocol {
        return MockSensorPairingService()
    }

    public override var bluetoothSearcher: BluetoothSearcher {
        return MockBluetoothSearcher()
    }

    public override func establishProxy() {
        // do nothing
    }

    private var sensorStartDate = Date().addingTimeInterval(TimeInterval(days: -1))

    public required init() {
        super.init()

        self.lastConnected =  Date()


        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(5*60), repeats: true) { [weak self]_ in
            self?.reportMockSample()
        }

        // Also trigger a sample immediately, for dev convenience.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.reportMockSample()
        }
    }

    private func reportMockSample() {
        let date = Date()
        let value = 110.0 + sin(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600 * 5) / (3600*5) * Double.pi * 2) * 60
        let quantity = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: value)
        let newSample = NewGlucoseSample(
            date: date,
            quantity: quantity,
            condition: nil,
            trend: nil,
            trendRate: nil,
            isDisplayOnly: false,
            wasUserEntered: false,
            syncIdentifier: "mock-libre + \(date)",
            device: testingDevice
        )
        log.debug("Reporting mock value of %{public}@", String(describing: value))

        // must be inside this handler as setobservables "depend" on latestbackfill
        let sensorData = MockSensorData(
            minutesSinceStart: Int(date.timeIntervalSince(sensorStartDate).minutes),
            maxMinutesWearTime: Int(TimeInterval(days: 14).minutes),
            state: .ready,
            serialNumber: "12345",
            footerCrc: 0xabcd,
            date: date)

        self.latestBackfill = LibreGlucose(unsmoothedGlucose: value, glucoseDouble: value, timestamp: date)

        self.setObservables(sensorData: sensorData, bleData: nil, metaData: nil)

        self.delegateQueue.async {
            self.cgmManagerDelegate?.cgmManager(self, hasNew: CGMReadingResult.newData([newSample]))
        }
    }
}

extension LibreDemoCGMManager: TestingCGMManager {
    func injectGlucoseSamples(_ pastSamples: [LoopKit.NewGlucoseSample], futureSamples: [LoopKit.NewGlucoseSample]) {
        // TODO: Support scenarios
    }

    var testingDevice: HKDevice {
        HKDevice(
            name: "LibreDemoCGM",
            manufacturer: "LoopKit",
            model: nil,
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
    }

    func acceptDefaultsAndSkipOnboarding() {
    }

    func trigger(action: LoopTestingKit.DeviceAction) {
        // TODO: Support scenario actions
    }
}
