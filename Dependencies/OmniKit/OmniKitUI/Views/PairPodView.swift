//
//  PairPodView.swift
//  OmniKit
//
//  Created by Pete Schwamb on 2/5/20.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct PairPodView: View {
    
    @ObservedObject var viewModel: PairPodViewModel
    
    @State private var cancelModalIsPresented: Bool = false
    
    var body: some View {
        GuidePage(content: {
            VStack {
                LeadingImage("PodBottom")

                HStack {
                    InstructionList(instructions: [
                        LocalizedString("Fill a new pod with U-100 Insulin (leave clear Pod needle cap on). Listen for 2 beeps.", comment: "Label text for step 1 of pair pod instructions"),
                        LocalizedString("Keep the RileyLink about 6 inches from the pod during pairing.", comment: "Label text for step 2 of pair pod instructions")
                    ])
                    .disabled(viewModel.state.instructionsDisabled)
                }
                .padding(.bottom, 8)
            }
            .accessibility(sortPriority: 1)
        }) {
            VStack {
                if self.viewModel.state.showProgressDetail {
                    self.viewModel.error.map {
                        ErrorView($0, errorClass: $0.recoverable ? .normal : .critical)
                            .accessibility(sortPriority: 0)
                    }

                    if self.viewModel.error == nil {
                        VStack {
                            ProgressIndicatorView(state: self.viewModel.state.progressState)
                            if self.viewModel.state.isFinished {
                                FrameworkLocalText("Paired", comment: "Label text indicating pairing finished.")
                                    .bold()
                                    .padding(.top)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
                if self.viewModel.error != nil && self.viewModel.podIsActivated {
                    Button(action: {
                        self.viewModel.didRequestDeactivation?()
                    }) {
                        Text(LocalizedString("Deactivate Pod", comment: "Button text for deactivate pod button"))
                            .accessibility(identifier: "button_deactivate_pod")
                            .actionButtonStyle(.destructive)
                    }
                    .disabled(self.viewModel.state.isProcessing)
                }
                
                if (self.viewModel.error == nil || self.viewModel.error?.recoverable == true) {
                    Button(action: {
                        self.viewModel.continueButtonTapped()
                    }) {
                        Text(self.viewModel.state.nextActionButtonDescription)
                            .accessibility(identifier: "button_next_action")
                            .accessibility(label: Text(self.viewModel.state.actionButtonAccessibilityLabel))
                            .actionButtonStyle(.primary)
                    }
                    .disabled(self.viewModel.state.isProcessing)
                    .animation(nil)
                    .zIndex(1)
                }
            }
            .transition(AnyTransition.opacity.combined(with: .move(edge: .bottom)))
            .padding()
        }
        .animation(.default)
        .alert(isPresented: $cancelModalIsPresented) { cancelPairingModal }
        .navigationBarTitle(LocalizedString("Pair Pod", comment: "Pair Pod navigationBarTitle"), displayMode: .automatic)
        .navigationBarBackButtonHidden(self.viewModel.backButtonHidden)
        .navigationBarItems(trailing: self.viewModel.state.navBarVisible ? cancelButton : nil)
    }
        
    var cancelButton: some View {
        Button(LocalizedString("Cancel", comment: "Cancel button text in navigation bar on pair pod UI")) {
            if viewModel.podIsActivated {
                cancelModalIsPresented = true
            } else {
                viewModel.didCancelSetup?()
            }
        }
        .accessibility(identifier: "button_cancel")
        .disabled(self.viewModel.state.isProcessing)
    }
    
    var cancelPairingModal: Alert {
        return Alert(
            title: FrameworkLocalText("Are you sure you want to cancel Pod setup?", comment: "Alert title for cancel pairing modal"),
            message: FrameworkLocalText("If you cancel Pod setup, the current Pod will be deactivated and will be unusable.", comment: "Alert message body for confirm pod attachment"),
            primaryButton: .destructive(FrameworkLocalText("Yes, Deactivate Pod", comment: "Button title for confirm deactivation option"), action: { viewModel.didRequestDeactivation?() }),
            secondaryButton: .default(FrameworkLocalText("No, Continue With Pod", comment: "Continue pairing button title of in pairing cancel modal"))
        )
    }

}
