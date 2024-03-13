import CGMBLEKit
import CGMBLEKitUI
import G7SensorKit
import G7SensorKitUI
import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

extension CGM {
    struct CGMSetupView: UIViewControllerRepresentable {
        let CGMType: CGMType
        let bluetoothManager: BluetoothStateManager
        let unit: GlucoseUnits
        weak var completionDelegate: CompletionDelegate?
        weak var setupDelegate: CGMManagerOnboardingDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<CGMSetupView>) -> UIViewController {
            var setupViewController: SetupUIResult<
                CGMManagerViewController,
                CGMManagerUI
            >?

            let displayGlucosePreference: DisplayGlucosePreference
            switch unit {
            case .mgdL:
                displayGlucosePreference = DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter)
            case .mmolL:
                displayGlucosePreference = DisplayGlucosePreference(displayGlucoseUnit: .millimolesPerLiter)
            }

            switch CGMType {
            case .dexcomG5:
                setupViewController = G5CGMManager.setupViewController(
                    bluetoothProvider: bluetoothManager,
                    displayGlucosePreference: displayGlucosePreference,
                    colorPalette: .default,
                    allowDebugFeatures: false
                )
            case .dexcomG6:
                setupViewController = G6CGMManager.setupViewController(
                    bluetoothProvider: bluetoothManager,
                    displayGlucosePreference: displayGlucosePreference,
                    colorPalette: .default,
                    allowDebugFeatures: false
                )
            case .dexcomG7:
                setupViewController =
                    G7CGMManager.setupViewController(
                        bluetoothProvider: bluetoothManager,
                        displayGlucosePreference: displayGlucosePreference,
                        colorPalette: .default,
                        allowDebugFeatures: false,
                        prefersToSkipUserInteraction: false
                    )
            default:
                break
            }

            switch setupViewController {
            case var .userInteractionRequired(setupViewControllerUI):
                setupViewControllerUI.cgmManagerOnboardingDelegate = setupDelegate
                setupViewControllerUI.completionDelegate = completionDelegate
                return setupViewControllerUI
            case let .createdAndOnboarded(cgmManagerUI):
                debug(.default, "CGM manager  created and onboarded")
                setupDelegate?.cgmManagerOnboarding(didCreateCGMManager: cgmManagerUI)
                return UIViewController()
            case .none:
                return UIViewController()
            }
        }

        func updateUIViewController(
            _ uiViewController: UIViewController,
            context _: UIViewControllerRepresentableContext<CGMSetupView>
        ) {
            uiViewController.isModalInPresentation = true
        }
    }
}
