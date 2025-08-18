//
//  DeactivatePodViewModel.swift
//  OmniBLE
//
//  Created by Pete Schwamb on 3/9/20.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKitUI

public protocol PodDeactivater {
    func deactivatePod(completion: @escaping (OmniBLEPumpManagerError?) -> Void)
    func forgetPod(completion: @escaping () -> Void)
}

extension OmniBLEPumpManager: PodDeactivater {}


class DeactivatePodViewModel: ObservableObject, Identifiable {
    
    enum DeactivatePodViewModelState {
        case active
        case deactivating
        case resultError(DeactivationError)
        case finished
        
        var actionButtonAccessibilityLabel: String {
            switch self {
            case .active:
                return LocalizedString("Deactivate Pod", comment: "Deactivate pod action button accessibility label while ready to deactivate")
            case .deactivating:
                return LocalizedString("Deactivating.", comment: "Deactivate pod action button accessibility label while deactivating")
            case .resultError(let error):
                return String(format: "%@ %@", error.errorDescription ?? "", error.recoverySuggestion ?? "")
            case .finished:
                return LocalizedString("Pod deactivated successfully. Continue.", comment: "Deactivate pod action button accessibility label when deactivation complete")
            }
        }

        var actionButtonDescription: String {
            switch self {
            case .active:
                return LocalizedString("Slide to Deactivate Pod", comment: "Action button description for deactivate while pod still active")
            case .resultError:
                return LocalizedString("Retry", comment: "Action button description for deactivate after failed attempt")
            case .deactivating:
                return LocalizedString("Deactivating...", comment: "Action button description while deactivating")
            case .finished:
                return LocalizedString("Continue", comment: "Action button description when deactivated")
            }
        }
        
        var actionButtonStyle: ActionButton.ButtonType {
            switch self {
            case .active:
                return .destructive
            default:
                return .primary
            }
        }

        
        var progressState: ProgressIndicatorState {
            switch self {
            case .active, .resultError:
                return .hidden
            case .deactivating:
                return .indeterminantProgress
            case .finished:
                return .completed
            }
        }
        
        var showProgressDetail: Bool {
            switch self {
            case .active:
                return false
            default:
                return true
            }
        }
        
        var isProcessing: Bool {
            switch self {
            case .deactivating:
                return true
            default:
                return false
            }
        }
        
        var isFinished: Bool {
            if case .finished = self {
                return true
            }
            return false
        }

    }
    
    @Published var state: DeactivatePodViewModelState = .active

    public var stateNeedsDeliberateUserAcceptance : Bool {
        switch state {
        case .active:
            true
        default:
            false
        }
    }

    var error: DeactivationError? {
        if case .resultError(let error) = self.state {
            return error
        }
        return nil
    }

    var didFinish: (() -> Void)?
    
    var didCancel: (() -> Void)?
    
    var podDeactivator: PodDeactivater

    var podAttachedToBody: Bool

    var instructionText: String

    init(podDeactivator: PodDeactivater, podAttachedToBody: Bool, fault: DetailedStatus?) {

        var text: String = ""
        if let faultEventCode = fault?.faultEventCode {
            let notificationString = faultEventCode.notificationTitle
            switch faultEventCode.faultType {
            case .exceededMaximumPodLife80Hrs, .reservoirEmpty, .occluded:
                // Just prepend a simple sentence with the notification string for these faults.
                // Other occluded related 0x6? faults will be treated as a general pod error as per the PDM.
                text = String(format: "%@. ", notificationString)
            default:
                // Display the fault code in decimal and hex, the fault description and the pdmRef string for other errors.
                text = String(format: "⚠️ %1$@ (0x%2$02X)\n%3$@\n", notificationString, faultEventCode.rawValue, faultEventCode.faultDescription)
                if let pdmRef = fault?.pdmRef {
                    text += LocalizedString("Ref: ", comment: "PDM Ref string line") + pdmRef + "\n\n"
                }
            }
        }

        if podAttachedToBody {
            text += LocalizedString("Please deactivate the pod. When deactivation is complete, you may remove it and pair a new pod.", comment: "Instructions for deactivate pod when pod is on body")
        } else {
            text += LocalizedString("Please deactivate the pod. When deactivation is complete, you may pair a new pod.", comment: "Instructions for deactivate pod when pod not on body")
        }

        self.podDeactivator = podDeactivator
        self.podAttachedToBody = podAttachedToBody
        self.instructionText = text
    }
    
    public func continueButtonTapped() {
        if case .finished = state {
            didFinish?()
        } else {
            self.state = .deactivating
            podDeactivator.deactivatePod { (error) in
                DispatchQueue.main.async {
                    if let error = error {
                        self.state = .resultError(DeactivationError.OmniBLEPumpManagerError(error))
                    } else {
                        self.discardPod(navigateOnCompletion: false)
                    }
                }
            }
        }
    }
    
    public func discardPod(navigateOnCompletion: Bool = true) {
        podDeactivator.forgetPod {
            DispatchQueue.main.async {
                if navigateOnCompletion {
                    self.didFinish?()
                } else {
                    self.state = .finished
                }
            }
        }
    }
}

enum DeactivationError : LocalizedError {
    case OmniBLEPumpManagerError(OmniBLEPumpManagerError)
    
    var recoverySuggestion: String? {
        switch self {
        case .OmniBLEPumpManagerError:
            return LocalizedString("There was a problem communicating with the pod. If this problem persists, tap Discard Pod. You can then activate a new Pod.", comment: "Format string for recovery suggestion during deactivate pod.")
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .OmniBLEPumpManagerError(let error):
            return error.errorDescription
        }
    }
}
