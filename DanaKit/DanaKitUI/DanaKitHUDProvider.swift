import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

internal class DanaKitHUDProvider: NSObject, HUDProvider {
    var managerIdentifier: String {
        pumpManager.managerIdentifier
    }

    private let pumpManager: DanaKitPumpManager

    private var reservoirView: DanaKitReservoirView?

    private let bluetoothProvider: BluetoothProvider

    private let colorPalette: LoopUIColorPalette

    private var refreshTimer: Timer?

    private let allowedInsulinTypes: [InsulinType]

    var visible: Bool = true {
        didSet {
            if oldValue != visible, visible {
                hudDidAppear()
            }
        }
    }

    public init(
        pumpManager: DanaKitPumpManager,
        bluetoothProvider: BluetoothProvider,
        colorPalette: LoopUIColorPalette,
        allowedInsulinTypes: [InsulinType]
    ) {
        self.pumpManager = pumpManager
        self.bluetoothProvider = bluetoothProvider
        self.colorPalette = colorPalette
        self.allowedInsulinTypes = allowedInsulinTypes
        super.init()
        self.pumpManager.addStateObserver(self, queue: .main)
    }

    public func createHUDView() -> BaseHUDView? {
        reservoirView = DanaKitReservoirView.instantiate()
        updateReservoirView()

        return reservoirView
    }

    public var hudViewRawState: HUDProvider.HUDViewRawState {
        var rawValue: HUDProvider.HUDViewRawState = [:]

        rawValue["lastStatusDate"] = pumpManager.rawState["lastStatusDate"]
        rawValue["reservoirLevel"] = pumpManager.rawState["reservoirLevel"]

        return rawValue
    }

    public func didTapOnHUDView(_: BaseHUDView, allowDebugFeatures _: Bool) -> HUDTapAction? {
        nil
    }

    private func hudDidAppear() {
        updateReservoirView()
        pumpManager.ensureCurrentPumpData { _ in
            DispatchQueue.main.async {
                self.updateReservoirView()
            }
        }
    }

    public static func createHUDView(rawValue: HUDProvider.HUDViewRawState) -> BaseHUDView? {
        let reservoirView: DanaKitReservoirView?

        if let lastStatusDate = rawValue["lastStatusDate"] as? Date {
            reservoirView = DanaKitReservoirView.instantiate()
            reservoirView!.update(level: rawValue["reservoirLevel"] as? Double, at: lastStatusDate)
        } else {
            reservoirView = nil
        }

        return reservoirView
    }

    private func updateReservoirView() {
        guard let reservoirView = reservoirView,
              let lastStatusDate = pumpManager.rawState["lastStatusDate"] as? Date
        else {
            return
        }

        reservoirView.update(level: pumpManager.rawState["reservoirLevel"] as? Double, at: lastStatusDate)
    }
}

extension DanaKitHUDProvider: StateObserver {
    func deviceScanDidUpdate(_: DanaPumpScan) {
        // Ble scan not needed here
    }

    func stateDidUpdate(_ state: DanaKitPumpManagerState, _: DanaKitPumpManagerState) {
        updateReservoirView()

        visible = state.deviceName != nil
    }
}
