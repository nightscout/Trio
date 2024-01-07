//
//  DeactivatePodView.swift
//  OmniBLE
//
//  Created by Pete Schwamb on 3/9/20.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI
import SlideButton

struct DeactivatePodView: View {
    
    @ObservedObject var viewModel: DeactivatePodViewModel

    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.guidanceColors) var guidanceColors
    
    @State private var removePodModalIsPresented: Bool = false

    var body: some View {
        GuidePage(content: {
            VStack {
                LeadingImage("Pod")

                HStack {
                    Text(viewModel.instructionText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }
            .padding(.bottom, 8)
        }) {
            VStack {
                if viewModel.state.showProgressDetail {
                    VStack {
                        viewModel.error.map {ErrorView($0).accessibility(sortPriority: 0)}
                        
                        if viewModel.error == nil {
                            VStack {
                                ProgressIndicatorView(state: viewModel.state.progressState)
                                if self.viewModel.state.isFinished {
                                    FrameworkLocalText("Deactivated", comment: "Label text showing pod is deactivated")
                                        .bold()
                                        .padding(.top)
                                }
                            }
                            .padding(.bottom, 8)
                        }

                    }
                    .transition(AnyTransition.opacity.combined(with: .move(edge: .bottom)))
                }
                if viewModel.error != nil {
                    Button(action: {
                        if viewModel.podAttachedToBody {
                            removePodModalIsPresented = true
                        } else {
                            viewModel.discardPod()
                        }
                    }) {
                        FrameworkLocalText("Discard Pod", comment: "Text for discard pod button")
                            .accessibility(identifier: "button_discard_pod_action")
                            .actionButtonStyle(.destructive)
                    }
                    .disabled(viewModel.state.isProcessing)
                }
                actionButton
                    .disabled(viewModel.state.isProcessing)
            }
            .padding()
        }
        .alert(isPresented: $removePodModalIsPresented) { removePodModal }
        .navigationBarTitle(LocalizedString("Deactivate Pod", comment: "navigation bar title for deactivate pod"), displayMode: .automatic)
        .navigationBarItems(trailing:
            Button("Cancel") {
                viewModel.didCancel?()
            }
        )
    }
    
    var removePodModal: Alert {
        return Alert(
            title: FrameworkLocalText("Remove Pod from Body", comment: "Title for remove pod modal"),
            message: FrameworkLocalText("Your Pod may still be delivering Insulin.\nRemove it from your body, then tap “Continue.“", comment: "Alert message body for confirm pod attachment"),
            primaryButton: .cancel(),
            secondaryButton: .default(FrameworkLocalText("Continue", comment: "Title of button to continue discard"), action: { viewModel.discardPod() })
        )
    }

    var actionText: some View {
        Text(self.viewModel.state.actionButtonDescription)
            .accessibility(identifier: "button_next_action")
            .accessibility(label: Text(self.viewModel.state.actionButtonAccessibilityLabel))
            .font(.headline)
    }

    @ViewBuilder
    var actionButton: some View {
        if self.viewModel.stateNeedsDeliberateUserAcceptance {
            SlideButton(styling: .init(indicatorSize: 60, indicatorColor: Color.red), action: {
                self.viewModel.continueButtonTapped()
            }) {
                actionText
            }
        } else {
            Button(action: {
                self.viewModel.continueButtonTapped()
            }) {
                actionText
                    .actionButtonStyle(.primary)
            }
        }
    }
}
