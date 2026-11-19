import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

extension CGMSettings {
    struct CGMSettingsView: UIViewControllerRepresentable {
        let cgmManager: CGMManagerUI?
        let bluetoothManager: BluetoothStateManager
        let unit: GlucoseUnits
        weak var completionDelegate: CompletionDelegate?

        final class Coordinator {
            let displayGlucosePreference: DisplayGlucosePreference

            init(displayGlucosePreference: DisplayGlucosePreference) {
                self.displayGlucosePreference = displayGlucosePreference
            }

            func updateDisplayGlucoseUnit(_ unit: GlucoseUnits) {
                let displayGlucoseUnit: LoopUnit = unit == .mgdL ? .milligramsPerDeciliter : .millimolesPerLiter
                displayGlucosePreference.unitDidChange(to: displayGlucoseUnit)
            }
        }

        func makeCoordinator() -> Coordinator {
            let displayGlucosePreference: DisplayGlucosePreference
            switch unit {
            case .mgdL:
                displayGlucosePreference = DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter)
            case .mmolL:
                displayGlucosePreference = DisplayGlucosePreference(displayGlucoseUnit: .millimolesPerLiter)
            }
            return Coordinator(displayGlucosePreference: displayGlucosePreference)
        }

        func makeUIViewController(context: UIViewControllerRepresentableContext<CGMSettingsView>) -> UIViewController {
            let displayGlucosePreference = context.coordinator.displayGlucosePreference
            guard let cgmManager = cgmManager else { return UIViewController() }

            var vc = cgmManager.settingsViewController(
                bluetoothProvider: bluetoothManager,
                displayGlucosePreference: displayGlucosePreference,
                colorPalette: .default,
                allowDebugFeatures: false
            )
            // vc.cgmManagerOnboardingDelegate =
            // vc.completionDelegate = self
            vc.completionDelegate = completionDelegate

            return vc
        }

        func updateUIViewController(
            _ uiViewController: UIViewController,
            context: UIViewControllerRepresentableContext<CGMSettingsView>
        ) {
            uiViewController.isModalInPresentation = true
            context.coordinator.updateDisplayGlucoseUnit(unit)
        }
    }
}
