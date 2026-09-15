import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

extension PumpConfig {
    struct PumpSetupView: UIViewControllerRepresentable {
        let pumpEntry: PumpCatalogEntry
        let pumpInitialSettings: PumpInitialSettings
        let bluetoothManager: BluetoothStateManager
        weak var completionDelegate: CompletionDelegate?
        weak var setupDelegate: PumpManagerOnboardingDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<PumpSetupView>) -> UIViewController {
            // var setupViewController: PumpManagerSetupViewController & UIViewController & CompletionNotifying
            var setupViewController: SetupUIResult<
                PumpManagerViewController,
                PumpManagerUI
            >

            let initialSettings = PumpManagerSetupSettings(
                maxBasalRateUnitsPerHour: pumpInitialSettings.maxBasalRateUnitsPerHour,
                maxBolusUnits: pumpInitialSettings.maxBolusUnits,
                basalSchedule: pumpInitialSettings.basalSchedule
            )

            let ManagerType = pumpEntry.manager
            setupViewController = ManagerType.setupViewController(
                initialSettings: initialSettings,
                bluetoothProvider: bluetoothManager,
                colorPalette: .default,
                allowDebugFeatures: true,
                prefersToSkipUserInteraction: false,
                allowedInsulinTypes: pumpEntry.allowedInsulinTypes
            )

            switch setupViewController {
            case var .userInteractionRequired(setupViewControllerUI):
                setupViewControllerUI.pumpManagerOnboardingDelegate = setupDelegate
                setupViewControllerUI.completionDelegate = completionDelegate
                return setupViewControllerUI
            case let .createdAndOnboarded(pumpManagerUI):
                debug(.default, "Pump manager  created and onboarded")
                setupDelegate?.pumpManagerOnboarding(didCreatePumpManager: pumpManagerUI)
                var vc = pumpManagerUI.settingsViewController(
                    bluetoothProvider: bluetoothManager,
                    pumpManagerOnboardingDelegate: setupDelegate
                )
                vc.completionDelegate = completionDelegate
                return vc
            }
        }

        func updateUIViewController(_: UIViewController, context _: UIViewControllerRepresentableContext<PumpSetupView>) {}
    }
}
