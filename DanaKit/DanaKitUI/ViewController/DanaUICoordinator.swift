import Combine
import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

enum DanaUIScreen {
    case debugView
    case firstRunScreen
    case danarsv1Explaination
    case danarsv1Password
    case danarsv3Explaination
    case danaiExplaination
    case insulinConfirmationScreen
    case bolusSpeedScreen
    case deviceScanningScreen
    case setupComplete
    case settings

    func next() -> DanaUIScreen? {
        switch self {
        case .debugView:
            return .firstRunScreen
        case .firstRunScreen:
            return nil
        case .danarsv1Explaination:
            return .danarsv1Password
        case .danarsv1Password:
            return .insulinConfirmationScreen
        case .danarsv3Explaination:
            return .insulinConfirmationScreen
        case .danaiExplaination:
            return .insulinConfirmationScreen
        case .insulinConfirmationScreen:
            return .bolusSpeedScreen
        case .bolusSpeedScreen:
            return .deviceScanningScreen
        case .deviceScanningScreen:
            return .setupComplete
        case .setupComplete:
            return nil
        case .settings:
            return nil
        }
    }
}

protocol DanaUINavigator: AnyObject {
    func navigateTo(_ screen: DanaUIScreen)
}

class DanaUICoordinator: UINavigationController, PumpManagerOnboarding, CompletionNotifying, UINavigationControllerDelegate {
    var pumpManagerOnboardingDelegate: PumpManagerOnboardingDelegate?

    var completionDelegate: CompletionDelegate?

    var screenStack = [DanaUIScreen]()
    var currentScreen: DanaUIScreen {
        screenStack.last!
    }

    private let colorPalette: LoopUIColorPalette

    private var pumpManager: DanaKitPumpManager?

    private var allowedInsulinTypes: [InsulinType]

    private var allowDebugFeatures: Bool

    init(
        pumpManager: DanaKitPumpManager? = nil,
        colorPalette: LoopUIColorPalette,
        pumpManagerSettings: PumpManagerSetupSettings? = nil,
        allowDebugFeatures: Bool,
        allowedInsulinTypes: [InsulinType] = []
    )
    {
        if pumpManager == nil, pumpManagerSettings == nil {
            self.pumpManager = DanaKitPumpManager(state: DanaKitPumpManagerState(rawValue: [:]))
        } else if pumpManager == nil, pumpManagerSettings != nil {
            let basal = DanaKitPumpManagerState.convertBasal(pumpManagerSettings!.basalSchedule.items)
            self.pumpManager = DanaKitPumpManager(state: DanaKitPumpManagerState(basalSchedule: basal))
        } else {
            self.pumpManager = pumpManager
        }

        self.colorPalette = colorPalette

        self.allowDebugFeatures = allowDebugFeatures

        self.allowedInsulinTypes = allowedInsulinTypes

        super.init(navigationBarClass: UINavigationBar.self, toolbarClass: UIToolbar.self)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if screenStack.isEmpty {
            screenStack = [getInitialScreen()]
            let viewController = viewControllerForScreen(currentScreen)
            viewController.isModalInPresentation = false
            setViewControllers([viewController], animated: false)
        }
    }

    private func hostingController<Content: View>(rootView: Content) -> DismissibleHostingController<some View> {
        let rootView = rootView
            .environment(\.appName, Bundle.main.bundleDisplayName)
        return DismissibleHostingController(content: rootView, colorPalette: colorPalette)
    }

    private func viewControllerForScreen(_ screen: DanaUIScreen) -> UIViewController {
        switch screen {
        case .debugView:
            let viewModel = DanaKitDebugViewModel(pumpManager)
            return hostingController(rootView: DanaKitDebugView(viewModel: viewModel))
        case .firstRunScreen:
            let view = DanaKitSetupView(
                nextAction: goToExplaination,
                debugAction: { self.navigateTo(.debugView) }
            ) // self.allowDebugFeatures ? { self.navigateTo(.debugView) } : {})
            return hostingController(rootView: view)
        case .danarsv1Explaination:
            let view = DanaRSv1Explaination(nextAction: stepFinished)
            return hostingController(rootView: view)
        case .danarsv1Password:
            let view = DanaRSv1Password(nextAction: { password in
                guard let pumpManager = self.pumpManager else {
                    self.stepFinished()
                    return
                }

                pumpManager.state.devicePassword = password
                self.stepFinished()
            })
            return hostingController(rootView: view)
        case .danarsv3Explaination:
            let view = DanaRSv3Explaination(nextAction: stepFinished)
            return hostingController(rootView: view)
        case .danaiExplaination:
            let view = DanaIExplainationView(nextAction: stepFinished)
            return hostingController(rootView: view)
        case .insulinConfirmationScreen:
            let confirm: (InsulinType) -> Void = { confirmedType in
                self.pumpManager?.state.insulinType = confirmedType
                self.stepFinished()
            }
            let view = InsulinTypeConfirmation(
                initialValue: allowedInsulinTypes[0],
                supportedInsulinTypes: allowedInsulinTypes,
                didConfirm: confirm
            )
            return hostingController(rootView: view)
        case .bolusSpeedScreen:
            let next: (BolusSpeed) -> Void = { bolusSpeed in
                self.pumpManager?.state.bolusSpeed = bolusSpeed
                self.stepFinished()
            }
            let view = DanaKitPumpSpeed(next: next)

            return hostingController(rootView: view)
        case .deviceScanningScreen:
            pumpManager?.state.isOnBoarded = true
            pumpManager?.notifyStateDidChange()
            pumpManagerOnboardingDelegate?.pumpManagerOnboarding(didOnboardPumpManager: pumpManager!)

            let viewModel = DanaKitScanViewModel(pumpManager, nextStep: stepFinished)
            return hostingController(rootView: DanaKitScanView(viewModel: viewModel))
        case .setupComplete:
            let nextStep: () -> Void = {
                self.pumpManagerOnboardingDelegate?.pumpManagerOnboarding(didCreatePumpManager: self.pumpManager!)
                self.completionDelegate?.completionNotifyingDidComplete(self)
            }

            let view = DanaKitSetupCompleteView(
                finish: nextStep,
                friendlyPumpModelName: pumpManager?.state.getFriendlyDeviceName() ?? "",
                imageName: pumpManager?.state.getDanaPumpImageName() ?? "danai"
            )
            return hostingController(rootView: view)
        case .settings:
            let view = DanaKitSettingsView(
                viewModel: DanaKitSettingsViewModel(pumpManager, stepFinished),
                supportedInsulinTypes: allowedInsulinTypes,
                imageName: pumpManager?.state.getDanaPumpImageName() ?? "danai"
            )
            return hostingController(rootView: view)
        }
    }

    func stepFinished() {
        if let nextStep = currentScreen.next() {
            navigateTo(nextStep)
        } else {
            pumpManager?.notifyDelegateOfDeactivation {
                self.completionDelegate?.completionNotifyingDidComplete(self)
            }
        }
    }

    func getInitialScreen() -> DanaUIScreen {
        guard let pumpManager = self.pumpManager else {
            return .firstRunScreen
        }

        if pumpManager.isOnboarded {
            return .settings
        }

        if pumpManager.state.insulinType != nil {
            return .deviceScanningScreen
        }

        return .firstRunScreen
    }

    func goToExplaination(_ index: Int) {
        switch index {
        case 0:
            navigateTo(.danarsv1Explaination)
            return
        case 1:
            navigateTo(.danarsv3Explaination)
            return
        case 2:
            navigateTo(.danaiExplaination)
            return
        default:
            return
        }
    }
}

extension DanaUICoordinator: DanaUINavigator {
    func navigateTo(_ screen: DanaUIScreen) {
        screenStack.append(screen)
        let viewController = viewControllerForScreen(screen)
        viewController.isModalInPresentation = false
        pushViewController(viewController, animated: true)
        viewController.view.layoutSubviews()
    }
}
