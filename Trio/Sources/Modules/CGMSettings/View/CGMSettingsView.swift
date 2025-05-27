//
// Trio
// CGMSettingsView.swift
// Created by Deniz Cengiz on 2025-02-17.
// Last edited by Deniz Cengiz on 2025-02-17.
// Most contributions by Pierre L and Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

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

        func makeUIViewController(context _: UIViewControllerRepresentableContext<CGMSettingsView>) -> UIViewController {
            let displayGlucosePreference: DisplayGlucosePreference
            switch unit {
            case .mgdL:
                displayGlucosePreference = DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter)
            case .mmolL:
                displayGlucosePreference = DisplayGlucosePreference(displayGlucoseUnit: .millimolesPerLiter)
            }

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
            context _: UIViewControllerRepresentableContext<CGMSettingsView>
        ) {
            uiViewController.isModalInPresentation = true
        }
    }
}
