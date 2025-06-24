//
//  OmnipodUICoordinator.swift
//  OmniKit
//
//  Created by Pete Schwamb on 2/16/20.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation

import UIKit
import SwiftUI
import Combine
import LoopKit
import LoopKitUI
import OmniKit
import RileyLinkKit
import RileyLinkBLEKit
import RileyLinkKitUI

enum OmnipodUIScreen {
    case firstRunScreen
    case expirationReminderSetup
    case lowReservoirReminderSetup
    case insulinTypeSelection
    case rileyLinkSetup
    case pairAndPrime
    case insertCannula
    case confirmAttachment
    case checkInsertedCannula
    case setupComplete
    case pendingCommandRecovery
    case uncertaintyRecovered
    case deactivate
    case settings

    func next() -> OmnipodUIScreen? {
        switch self {
        case .firstRunScreen:
            return .expirationReminderSetup
        case .expirationReminderSetup:
            return .lowReservoirReminderSetup
        case .lowReservoirReminderSetup:
            return .insulinTypeSelection
        case .insulinTypeSelection:
            return .rileyLinkSetup
        case .rileyLinkSetup:
            return .pairAndPrime
        case .pairAndPrime:
            return .confirmAttachment
        case .confirmAttachment:
            return .insertCannula
        case .insertCannula:
            return .checkInsertedCannula
        case .checkInsertedCannula:
            return .setupComplete
        case .setupComplete:
            return nil
        case .pendingCommandRecovery:
            return .deactivate
        case .uncertaintyRecovered:
            return nil
        case .deactivate:
            return .pairAndPrime
        case .settings:
            return nil
        }
    }
}

class OmnipodUICoordinator: UINavigationController, PumpManagerOnboarding, CompletionNotifying, UINavigationControllerDelegate {

    public weak var pumpManagerOnboardingDelegate: PumpManagerOnboardingDelegate?

    public weak var completionDelegate: CompletionDelegate?

    var pumpManager: OmnipodPumpManager

    private var disposables = Set<AnyCancellable>()

    var currentScreen: OmnipodUIScreen {
        return screenStack.last!
    }

    var screenStack = [OmnipodUIScreen]()

    private let colorPalette: LoopUIColorPalette

    private var pumpManagerType: OmnipodPumpManager.Type?

    private var allowedInsulinTypes: [InsulinType]

    private var allowDebugFeatures: Bool

    private func viewControllerForScreen(_ screen: OmnipodUIScreen) -> UIViewController {
        switch screen {
        case .firstRunScreen:
            let view = PodSetupView(nextAction: { [weak self] in self?.stepFinished() },
                                    allowDebugFeatures: allowDebugFeatures,
                                    skipOnboarding: { [weak self] in    // NOTE: DEBUG FEATURES - DEBUG AND TEST ONLY
                                        guard let self = self else { return }
                                        self.pumpManager.completeOnboard()
                                        self.completionDelegate?.completionNotifyingDidComplete(self)
                                    })
            return hostingController(rootView: view)
        case .rileyLinkSetup:
            let dataSource = RileyLinkListDataSource(rileyLinkPumpManager: pumpManager)
            var view = RileyLinkSetupView(
                dataSource: dataSource,
                nextAction: { [weak self] in self?.stepFinished() })
            view.cancelButtonTapped = { [weak self] in
                 self?.setupCanceled()
            }
            return hostingController(rootView: view)

        case .expirationReminderSetup:
            var view = ExpirationReminderSetupView(expirationReminderDefault: Int(pumpManager.defaultExpirationReminderOffset.hours))
            view.valueChanged = { [weak self] value in
                self?.pumpManager.defaultExpirationReminderOffset = .hours(Double(value))
            }
            view.continueButtonTapped = { [weak self] in
                guard let self = self else { return }
                if !self.pumpManager.isOnboarded {
                    self.pumpManager.completeOnboard()
                    self.pumpManagerOnboardingDelegate?.pumpManagerOnboarding(didOnboardPumpManager: self.pumpManager)
                }
                self.stepFinished()
            }
            view.cancelButtonTapped = { [weak self] in
                self?.setupCanceled()
            }
            let hostedView = hostingController(rootView: view)
            hostedView.navigationItem.title = LocalizedString("Expiration Reminder", comment: "Title for ExpirationReminderSetupView")
            return hostedView
        case .lowReservoirReminderSetup:
            var view = LowReservoirReminderSetupView(lowReservoirReminderValue: Int(pumpManager.lowReservoirReminderValue))
            view.valueChanged = { [weak self] value in
                self?.pumpManager.lowReservoirReminderValue = Double(value)
            }
            view.continueButtonTapped = { [weak self] in
                self?.pumpManager.initialConfigurationCompleted = true
                self?.stepFinished()
            }
            view.cancelButtonTapped = { [weak self] in
                self?.setupCanceled()
            }
            let hostedView = hostingController(rootView: view)
            hostedView.navigationItem.title = LocalizedString("Low Reservoir", comment: "Title for LowReservoirReminderSetupView")
            hostedView.navigationItem.backButtonDisplayMode = .generic
            return hostedView
        case .insulinTypeSelection:
            let didConfirm: (InsulinType) -> Void = { [weak self] (confirmedType) in
                self?.pumpManager.insulinType = confirmedType
                self?.stepFinished()
            }
            let didCancel: () -> Void = { [weak self] in
                self?.setupCanceled()
            }

            let insulinSelectionView = InsulinTypeConfirmation(initialValue: .novolog, supportedInsulinTypes: allowedInsulinTypes, didConfirm: didConfirm, didCancel: didCancel)
            let hostedView = hostingController(rootView: insulinSelectionView)
            hostedView.navigationItem.title = LocalizedString("Insulin Type", comment: "Title for insulin type selection screen")
            return hostedView
        case .deactivate:
            let viewModel = DeactivatePodViewModel(podDeactivator: pumpManager, podAttachedToBody: pumpManager.podAttachmentConfirmed, fault: pumpManager.state.podState?.fault)

            viewModel.didFinish = { [weak self] in
                self?.stepFinished()
            }
            viewModel.didCancel = { [weak self] in
                self?.setupCanceled()
            }
            let view = DeactivatePodView(viewModel: viewModel)
            let hostedView = hostingController(rootView: view)
            hostedView.navigationItem.title = LocalizedString("Deactivate Pod", comment: "Title for deactivate pod screen")
            return hostedView
        case .settings:
            let viewModel = OmnipodSettingsViewModel(pumpManager: pumpManager)
            viewModel.didFinish = { [weak self] in
                self?.stepFinished()
            }
            viewModel.navigateTo = { [weak self] (screen) in
                self?.navigateTo(screen)
            }
            let rileyLinkListDataSource = RileyLinkListDataSource(rileyLinkPumpManager: pumpManager)

            let handleRileyLinkSelection = { [weak self] (device: RileyLinkDevice) in
                if let self = self {
                    let vc = RileyLinkDeviceTableViewController(
                        device: device,
                        batteryAlertLevel: self.pumpManager.rileyLinkBatteryAlertLevel,
                        batteryAlertLevelChanged: { [weak self] value in
                            self?.pumpManager.rileyLinkBatteryAlertLevel = value
                        }
                    )
                    self.show(vc, sender: self)
                }
            }

            let view = OmnipodSettingsView(viewModel: viewModel, rileyLinkListDataSource: rileyLinkListDataSource, handleRileyLinkSelection: handleRileyLinkSelection, supportedInsulinTypes: allowedInsulinTypes)
            return hostingController(rootView: view)
        case .pairAndPrime:
            pumpManagerOnboardingDelegate?.pumpManagerOnboarding(didCreatePumpManager: pumpManager)

            let viewModel = PairPodViewModel(podPairer: pumpManager)

            viewModel.didFinish = { [weak self] in
                self?.stepFinished()
            }
            viewModel.didCancelSetup = { [weak self] in
                self?.setupCanceled()
            }
            viewModel.didRequestDeactivation = { [weak self] in
                self?.navigateTo(.deactivate)
            }

            let view = hostingController(rootView: PairPodView(viewModel: viewModel))
            view.navigationItem.title = LocalizedString("Pair Pod", comment: "Title for pod pairing screen")
            view.navigationItem.backButtonDisplayMode = .generic
            return view
        case .confirmAttachment:
            let view = AttachPodView(
                didConfirmAttachment: { [weak self] in
                    self?.pumpManager.podAttachmentConfirmed = true
                    self?.stepFinished()
                },
                didRequestDeactivation: { [weak self] in
                    self?.navigateTo(.deactivate)
                })

            let vc = hostingController(rootView: view)
            vc.navigationItem.title = LocalizedString("Attach Pod", comment: "Title for Attach Pod screen")
            vc.navigationItem.hidesBackButton = true
            return vc

        case .insertCannula:
            let viewModel = InsertCannulaViewModel(cannulaInserter: pumpManager)

            viewModel.didFinish = { [weak self] in
                self?.stepFinished()
            }
            viewModel.didRequestDeactivation = { [weak self] in
                self?.navigateTo(.deactivate)
            }

            let view = hostingController(rootView: InsertCannulaView(viewModel: viewModel))
            view.navigationItem.title = LocalizedString("Insert Cannula", comment: "Title for insert cannula screen")
            view.navigationItem.hidesBackButton = true
            return view
        case .checkInsertedCannula:
            let view = CheckInsertedCannulaView(
                didRequestDeactivation: { [weak self] in
                    self?.navigateTo(.deactivate)
                },
                wasInsertedProperly: { [weak self] in
                    self?.stepFinished()
                }
            )
            let hostedView = hostingController(rootView: view)
            hostedView.navigationItem.title = LocalizedString("Check Cannula", comment: "Title for check cannula screen")
            hostedView.navigationItem.hidesBackButton = true
            return hostedView
        case .setupComplete:
            guard let podExpiresAt = pumpManager.expiresAt,
                  let allowedExpirationReminderDates = pumpManager.allowedExpirationReminderDates
            else {
                fatalError("Cannot show setup complete UI without expiration and allowed reminder dates.")
            }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short

            let view = SetupCompleteView(
                scheduledReminderDate: pumpManager.scheduledExpirationReminder,
                dateFormatter: formatter,
                allowedDates: allowedExpirationReminderDates,
                onSaveScheduledExpirationReminder: { [weak self] (newExpirationReminderDate, completion) in
                    var intervalBeforeExpiration : TimeInterval?
                    if let newExpirationReminderDate = newExpirationReminderDate {
                        intervalBeforeExpiration = podExpiresAt.timeIntervalSince(newExpirationReminderDate)
                    }
                    self?.pumpManager.updateExpirationReminder(intervalBeforeExpiration, completion: completion)
                },
                didFinish: { [weak self] in
                    self?.stepFinished()
                },
                didRequestDeactivation: { [weak self] in
                    self?.navigateTo(.deactivate)
                }
            )

            let hostedView = hostingController(rootView: view)
            hostedView.navigationItem.title = LocalizedString("Setup Complete", comment: "Title for setup complete screen")
            return hostedView
        case .pendingCommandRecovery:
            if let pendingCommand = pumpManager.state.podState?.unacknowledgedCommand, pumpManager.state.podState?.needsCommsRecovery == true {

                let model = DeliveryUncertaintyRecoveryViewModel(appName: appName, uncertaintyStartedAt: pendingCommand.commandDate)
                model.didRecover = { [weak self] in
                    self?.navigateTo(.uncertaintyRecovered)
                }
                model.onDeactivate = { [weak self] in
                    self?.navigateTo(.deactivate)
                }
                model.onDismiss = { [weak self] in
                    if let self = self {
                        self.completionDelegate?.completionNotifyingDidComplete(self)
                    }
                }
                pumpManager.getPodStatus() { _ in }

                let handleRileyLinkSelection = { [weak self] (device: RileyLinkDevice) in
                    if let self = self {
                        let vc = RileyLinkDeviceTableViewController(
                            device: device,
                            batteryAlertLevel: self.pumpManager.rileyLinkBatteryAlertLevel,
                            batteryAlertLevelChanged: { [weak self] value in
                                self?.pumpManager.rileyLinkBatteryAlertLevel = value
                            }
                        )
                        self.show(vc, sender: self)
                    }
                }

                let dataSource = RileyLinkListDataSource(rileyLinkPumpManager: pumpManager)
                let view = DeliveryUncertaintyRecoveryView(model: model, rileyLinkListDataSource: dataSource, handleRileyLinkSelection: handleRileyLinkSelection)

                let hostedView = hostingController(rootView: view)
                hostedView.navigationItem.title = LocalizedString("Unable To Reach Pod", comment: "Title for pending command recovery screen")
                return hostedView
            } else {
                fatalError("Pending command recovery UI attempted without pending command")
            }
        case .uncertaintyRecovered:
            var view = UncertaintyRecoveredView(appName: appName)
            view.didFinish = { [weak self] in
                self?.stepFinished()
            }
            let hostedView = hostingController(rootView: view)
            hostedView.navigationItem.title = LocalizedString("Comms Recovered", comment: "Title for uncertainty recovered screen")
            return hostedView
        }
    }

    private func hostingController<Content: View>(rootView: Content) -> DismissibleHostingController {
        return DismissibleHostingController(rootView: rootView, colorPalette: colorPalette)
    }

    private func stepFinished() {
        if let nextStep = currentScreen.next() {
            navigateTo(nextStep)
        } else {
            completionDelegate?.completionNotifyingDidComplete(self)
        }
    }

    func navigateTo(_ screen: OmnipodUIScreen) {
        screenStack.append(screen)
        let viewController = viewControllerForScreen(screen)
        viewController.isModalInPresentation = false
        self.pushViewController(viewController, animated: true)
        viewController.view.layoutSubviews()
    }

    private func setupCanceled() {
        completionDelegate?.completionNotifyingDidComplete(self)
    }

    init(pumpManager: OmnipodPumpManager? = nil, colorPalette: LoopUIColorPalette, pumpManagerSettings: PumpManagerSetupSettings? = nil, allowDebugFeatures: Bool, allowedInsulinTypes: [InsulinType] = [])
    {
        if pumpManager == nil, let pumpManagerSettings = pumpManagerSettings {
            let basalSchedule = pumpManagerSettings.basalSchedule

            let deviceProvider = RileyLinkBluetoothDeviceProvider(autoConnectIDs: [])

            let pumpManagerState = OmnipodPumpManagerState(
                isOnboarded: false,
                podState: nil,
                timeZone: basalSchedule.timeZone,
                basalSchedule: BasalSchedule(repeatingScheduleValues: basalSchedule.items),
                rileyLinkConnectionManagerState: nil,
                insulinType: nil,
                maximumTempBasalRate: pumpManagerSettings.maxBasalRateUnitsPerHour)

            self.pumpManager = OmnipodPumpManager(state: pumpManagerState, rileyLinkDeviceProvider: deviceProvider)
        } else {
            guard let pumpManager = pumpManager else {
                fatalError("Unable to create Omnipod PumpManager")
            }
            self.pumpManager = pumpManager
        }

        self.colorPalette = colorPalette

        self.allowDebugFeatures = allowDebugFeatures

        self.allowedInsulinTypes = allowedInsulinTypes

        super.init(navigationBarClass: UINavigationBar.self, toolbarClass: UIToolbar.self)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func determineInitialStep() -> OmnipodUIScreen {
        if pumpManager.state.podState?.needsCommsRecovery == true {
            return .pendingCommandRecovery
        } else if pumpManager.podCommState == .activating {
            if pumpManager.podAttachmentConfirmed {
                return .insertCannula
            } else {
                return .pairAndPrime // need to finish the priming
            }
        } else if !pumpManager.isOnboarded {
            if !pumpManager.initialConfigurationCompleted {
                return .firstRunScreen
            }
            return .pairAndPrime // pair and prime a new pod
        } else {
            return .settings
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if screenStack.isEmpty {
            screenStack = [determineInitialStep()]
            let viewController = viewControllerForScreen(currentScreen)
            viewController.isModalInPresentation = false
            setViewControllers([viewController], animated: false)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        completionDelegate?.completionNotifyingDidComplete(self)
    }

    var customTraitCollection: UITraitCollection {
        // Select height reduced layouts on iPhone SE and iPod Touch,
        // and select regular width layouts on larger screens, for list rendering styles
        if UIScreen.main.bounds.height <= 640 {
            return UITraitCollection(traitsFrom: [super.traitCollection, UITraitCollection(verticalSizeClass: .compact)])
        } else {
            return UITraitCollection(traitsFrom: [super.traitCollection, UITraitCollection(horizontalSizeClass: .regular)])
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationBar.prefersLargeTitles = true
        delegate = self
    }

    public func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {

        setOverrideTraitCollection(customTraitCollection, forChild: viewController)

        if viewControllers.count < screenStack.count {
            // Navigation back
            let _ = screenStack.popLast()
        }
        viewController.view.backgroundColor = UIColor.secondarySystemBackground
    }

    let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as! String
}
