//
// Trio
// TidepoolConfigView.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Pierre L and dsnallfot.
//
// Documentation available under: https://triodocs.org/

import Foundation
import LoopKit
import LoopKitUI
import SwiftUI

struct TidepoolSetupView: UIViewControllerRepresentable {
    let serviceUIType: ServiceUI.Type
    let pluginHost: PluginHost
    let serviceOnBoardDelegate: ServiceOnboardingDelegate
    let serviceDelegate: CompletionDelegate

    func makeUIViewController(context _: UIViewControllerRepresentableContext<TidepoolSetupView>) -> UIViewController {
        let result = serviceUIType.setupViewController(
            colorPalette: .default,
            pluginHost: pluginHost
        )
        switch result {
        case let .createdAndOnboarded(serviceUI):
            serviceOnBoardDelegate.serviceOnboarding(didCreateService: serviceUI)
            serviceOnBoardDelegate.serviceOnboarding(didOnboardService: serviceUI)
            return UIViewController()
        case var .userInteractionRequired(setupViewControllerUI):
            setupViewControllerUI.serviceOnboardingDelegate = serviceOnBoardDelegate
            setupViewControllerUI.completionDelegate = serviceDelegate
            return setupViewControllerUI
        }
    }

    func updateUIViewController(_: UIViewController, context _: UIViewControllerRepresentableContext<TidepoolSetupView>) {}
}

struct TidepoolSettingsView: UIViewControllerRepresentable {
    let serviceUI: ServiceUI
    let serviceOnBoardDelegate: ServiceOnboardingDelegate
    let serviceDelegate: CompletionDelegate?

    func makeUIViewController(context _: UIViewControllerRepresentableContext<TidepoolSettingsView>) -> UIViewController {
        var vc = serviceUI.settingsViewController(colorPalette: .default)
        vc.completionDelegate = serviceDelegate
        vc.serviceOnboardingDelegate = serviceOnBoardDelegate
        return vc
    }

    func updateUIViewController(_: UIViewController, context _: UIViewControllerRepresentableContext<TidepoolSettingsView>) {}
}
