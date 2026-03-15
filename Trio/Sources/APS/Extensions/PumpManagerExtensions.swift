import LoopKit
import LoopKitUI

extension PumpManager {
    typealias RawValue = [String: Any]

    var rawValue: [String: Any] {
        [
            "managerIdentifier": pluginIdentifier, // "managerIdentifier": type(of: self).managerIdentifier,
            "state": rawState
        ]
    }
}

extension PumpManagerUI {
    func settingsViewController(
        bluetoothProvider: BluetoothProvider,
        pumpManagerOnboardingDelegate: PumpManagerOnboardingDelegate?
    ) -> UIViewController & CompletionNotifying {
        var vc = settingsViewController(
            bluetoothProvider: bluetoothProvider,
            colorPalette: .default,
            allowDebugFeatures: true,
            allowedInsulinTypes: [.apidra, .humalog, .novolog, .fiasp, .lyumjev]
        )
        vc.pumpManagerOnboardingDelegate = pumpManagerOnboardingDelegate
        return vc
    }
}

protocol PumpSettingsBuilder {
    func settingsViewController() -> UIViewController & CompletionNotifying
}
