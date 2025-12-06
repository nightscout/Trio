import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

extension CGMSettings {
    struct CGMSetupView: UIViewControllerRepresentable {
        let CGMType: CGMModel
        let bluetoothManager: BluetoothStateManager
        let unit: GlucoseUnits
        weak var completionDelegate: CompletionDelegate?
        weak var setupDelegate: CGMManagerOnboardingDelegate?
        let pluginCGMManager: PluginManager

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

            switch CGMType.type {
            case .plugin:
                if let cgmManagerUIType = pluginCGMManager.getCGMManagerTypeByIdentifier(CGMType.id) {
                    setupViewController = cgmManagerUIType.setupViewController(
                        bluetoothProvider: bluetoothManager,
                        displayGlucosePreference: displayGlucosePreference,
                        colorPalette: .default,
                        allowDebugFeatures: false,
                        prefersToSkipUserInteraction: false
                    )
                } else {
                    break
                }
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
