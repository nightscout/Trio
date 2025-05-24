//
// Trio
// PumpManagerExtensions.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou and Jon B Mårtensson.
//
// Documentation available under: https://triodocs.org/

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
