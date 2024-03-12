//
//  G7UICoordinator.swift
//  CGMBLEKitUI
//
//  Created by Pete Schwamb on 9/24/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKitUI
import G7SensorKit

class G7UICoordinator: UINavigationController, CGMManagerOnboarding, CompletionNotifying, UINavigationControllerDelegate {
    var cgmManagerOnboardingDelegate: LoopKitUI.CGMManagerOnboardingDelegate?
    var completionDelegate: LoopKitUI.CompletionDelegate?
    var cgmManager: G7CGMManager?
    var displayGlucosePreference: DisplayGlucosePreference

    var colorPalette: LoopUIColorPalette

    init(cgmManager: G7CGMManager? = nil,
         colorPalette: LoopUIColorPalette,
         displayGlucosePreference: DisplayGlucosePreference,
         allowDebugFeatures: Bool)
    {
        self.cgmManager = cgmManager
        self.colorPalette = colorPalette
        self.displayGlucosePreference = displayGlucosePreference
        super.init(navigationBarClass: UINavigationBar.self, toolbarClass: UIToolbar.self)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self

        navigationBar.prefersLargeTitles = true // Ensure nav bar text is displayed correctly

        let viewController = initialView()
        setViewControllers([viewController], animated: false)
    }

    private func initialView() -> UIViewController {
        if cgmManager == nil {
            let rootView = G7StartupView(
                didContinue: { [weak self] in self?.completeSetup() },
                didCancel: { [weak self] in
                    if let self = self {
                        self.completionDelegate?.completionNotifyingDidComplete(self)
                    }
                }
            )
            let hostingController = DismissibleHostingController(content: rootView, colorPalette: colorPalette)
            hostingController.navigationItem.largeTitleDisplayMode = .never
            hostingController.title = nil
            return hostingController
        } else {
            let view = G7SettingsView(
                didFinish: { [weak self] in
                    if let self = self {
                        self.completionDelegate?.completionNotifyingDidComplete(self)
                    }
                },
                deleteCGM: { [ weak self] in
                    self?.cgmManager?.notifyDelegateOfDeletion {
                        DispatchQueue.main.async {
                            if let self = self {
                                self.completionDelegate?.completionNotifyingDidComplete(self)
                                self.dismiss(animated: true)
                            }
                        }
                    }
                },
                viewModel: G7SettingsViewModel(cgmManager: cgmManager!, displayGlucosePreference: displayGlucosePreference)
            )
            let hostingController = DismissibleHostingController(content: view, colorPalette: colorPalette)
            return hostingController
        }
    }

    func completeSetup() {
        cgmManager = G7CGMManager()
        cgmManagerOnboardingDelegate?.cgmManagerOnboarding(didCreateCGMManager: cgmManager!)
        cgmManagerOnboardingDelegate?.cgmManagerOnboarding(didOnboardCGMManager: cgmManager!)
        completionDelegate?.completionNotifyingDidComplete(self)
    }
}
