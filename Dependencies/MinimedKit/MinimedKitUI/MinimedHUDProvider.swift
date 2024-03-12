//
//  MinimedHUDProvider.swift
//  MinimedKitUI
//
//  Created by Pete Schwamb on 2/4/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopKitUI
import MinimedKit
import SwiftUI

class MinimedHUDProvider: HUDProvider {

    var managerIdentifier: String {
        return MinimedPumpManager.pluginIdentifier
    }

    private var state: MinimedPumpManagerState {
        didSet {
            guard visible else {
                return
            }

            if oldValue.lastReservoirReading != state.lastReservoirReading {
                self.updateReservoirView()
            }
        }
    }

    private let pumpManager: MinimedPumpManager

    private let bluetoothProvider: BluetoothProvider
    
    private let colorPalette: LoopUIColorPalette

    private let allowedInsulinTypes: [InsulinType]
    
    public init(pumpManager: MinimedPumpManager, bluetoothProvider: BluetoothProvider, colorPalette: LoopUIColorPalette, allowedInsulinTypes: [InsulinType]) {
        self.pumpManager = pumpManager
        self.bluetoothProvider = bluetoothProvider
        self.state = pumpManager.state
        self.colorPalette = colorPalette
        self.allowedInsulinTypes = allowedInsulinTypes
        pumpManager.stateObservers.insert(self, queue: .main)
    }

    var visible: Bool = false {
        didSet {
            if oldValue != visible && visible {
                self.updateReservoirView()
            }
        }
    }

    private weak var reservoirView: ReservoirHUDView?

    private func updateReservoirView() {
        if let lastReservoirVolume = state.lastReservoirReading,
            let reservoirView = reservoirView
        {
            let reservoirLevel = (lastReservoirVolume.units / pumpManager.pumpReservoirCapacity).clamped(to: 0...1.0)
            reservoirView.level = reservoirLevel
            reservoirView.setReservoirVolume(volume: lastReservoirVolume.units, at: lastReservoirVolume.validAt)
        }
    }

    public func createHUDView() -> BaseHUDView? {

        reservoirView = ReservoirHUDView.instantiate()

        if visible {
            updateReservoirView()
        }

        return reservoirView
    }

    public func didTapOnHUDView(_ view: BaseHUDView, allowDebugFeatures: Bool) -> HUDTapAction? {
        let vc = pumpManager.settingsViewController(bluetoothProvider: bluetoothProvider, colorPalette: colorPalette, allowDebugFeatures: allowDebugFeatures, allowedInsulinTypes: allowedInsulinTypes)
        return HUDTapAction.presentViewController(vc)
    }

    public var hudViewRawState: HUDProvider.HUDViewRawState {
        var rawValue: HUDProvider.HUDViewRawState = [
            "pumpReservoirCapacity": pumpManager.pumpReservoirCapacity
        ]

        if let lastReservoirReading = state.lastReservoirReading {
            rawValue["lastReservoirReading"] = lastReservoirReading.rawValue
        }

        return rawValue
    }

    public static func createHUDView(rawValue: HUDProvider.HUDViewRawState) -> BaseHUDView? {
        guard let pumpReservoirCapacity = rawValue["pumpReservoirCapacity"] as? Double else {
            return nil
        }

        let reservoirHUDView = ReservoirHUDView.instantiate()
        if let rawLastReservoirReading = rawValue["lastReservoirReading"] as? ReservoirReading.RawValue,
            let lastReservoirReading = ReservoirReading(rawValue: rawLastReservoirReading)
        {
            let reservoirLevel = (lastReservoirReading.units / pumpReservoirCapacity).clamped(to: 0...1.0)
            reservoirHUDView.level = reservoirLevel
            reservoirHUDView.setReservoirVolume(volume: lastReservoirReading.units, at: lastReservoirReading.validAt)
        }
        
        return reservoirHUDView
    }
}

extension MinimedHUDProvider: MinimedPumpManagerStateObserver {
    func didUpdatePumpManagerState(_ state: MinimedPumpManagerState) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.state = state
    }
}
