//
//  AttachPodView.swift
//  OmniBLE
//
//  Created by Pete Schwamb on 2/23/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct AttachPodView: View {
    
    enum Modal: Int, Identifiable {
        var id: Int { rawValue }
        
        case attachConfirmationModal
        case cancelModal
    }
    
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    var didConfirmAttachment: () -> Void
    var didRequestDeactivation: () -> Void
    
    @State private var activeModal: Modal?
    
    var body: some View {
        GuidePage(content: {
            VStack {
                LeadingImage("Pod")

                HStack {
                    InstructionList(instructions: [
                        LocalizedString("Prepare site.", comment: "Label text for step one of attach pod instructions"),
                        LocalizedString("Remove the Pod's blue needle cap and check cannula. Then remove paper backing.", comment: "Label text for step 1 of pair pod instructions "),
                        LocalizedString("Check Pod, apply to site, then confirm pod attachment.", comment: "Label text for step three of attach pod instructions")
                    ])
                }
                .padding(.bottom, 8)
            }
            .accessibility(sortPriority: 1)
        }) {
            Button(action: {
                activeModal = .attachConfirmationModal
            }) {
                FrameworkLocalText("Continue", comment: "Action button title for attach pod view")
                    .accessibility(identifier: "button_next_action")
                    .actionButtonStyle(.primary)
            }
            .animation(nil)
            .padding()
            .background(Color(UIColor.systemBackground))
            .zIndex(1)
        }
        .animation(.default)
        .alert(item: $activeModal, content: self.alert(for:))
        .navigationBarTitle(LocalizedString("Attach Pod", comment: "navigation bar title attach pod"), displayMode: .automatic)
        .navigationBarItems(trailing: cancelButton)
        .navigationBarBackButtonHidden(true)
    }
    
    var cancelButton: some View {
        Button(LocalizedString("Cancel", comment: "Cancel button text in navigation bar on pair pod UI")) {
            activeModal = .cancelModal
        }
        .accessibility(identifier: "button_cancel")
    }

    private func alert(for modal: Modal) -> Alert {
        switch modal {
        case .attachConfirmationModal:
            return confirmationModal
        case .cancelModal:
            return cancelPairingModal
        }
    }
    
    var confirmationModal: Alert {
        return Alert(
            title: FrameworkLocalText("Confirm Pod Attachment", comment: "Alert title for confirm pod attachment"),
            message: FrameworkLocalText("Please confirm that the Pod is securely attached to your body.\n\nThe cannula can be inserted only once with each Pod. Tap “Confirm” when Pod is attached.", comment: "Alert message body for confirm pod attachment"),
            primaryButton: .default(FrameworkLocalText("Confirm", comment: "Button title for confirm attachment option"), action: didConfirmAttachment),
            secondaryButton: .cancel()
        )
    }
    
    var cancelPairingModal: Alert {
        return Alert(
            title: FrameworkLocalText("Are you sure you want to cancel Pod setup?", comment: "Alert title for cancel pairing modal"),
            message: FrameworkLocalText("If you cancel Pod setup, the current Pod will be deactivated and will be unusable.", comment: "Alert message body for confirm pod attachment"),
            primaryButton: .destructive(FrameworkLocalText("Yes, Deactivate Pod", comment: "Button title for confirm deactivation option"), action: didRequestDeactivation),
            secondaryButton: .default(FrameworkLocalText("No, Continue With Pod", comment: "Continue pairing button title of in pairing cancel modal"))
        )
    }
}

struct AttachPodView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ZStack {
                Color(UIColor.secondarySystemBackground).edgesIgnoringSafeArea(.all)
                AttachPodView(didConfirmAttachment: {}, didRequestDeactivation: {})
            }
        }
    }
}
