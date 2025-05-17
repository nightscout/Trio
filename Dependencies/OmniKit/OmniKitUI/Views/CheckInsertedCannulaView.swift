//
//  CheckInsertedCannulaView.swift
//  OmniKit
//
//  Created by Pete Schwamb on 4/3/20.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct CheckInsertedCannulaView: View {
    
    
    @State private var cancelModalIsPresented: Bool = false
    
    private var didRequestDeactivation: () -> Void
    private var wasInsertedProperly: () -> Void

    init(didRequestDeactivation: @escaping () -> Void, wasInsertedProperly: @escaping () -> Void) {
        self.didRequestDeactivation = didRequestDeactivation
        self.wasInsertedProperly = wasInsertedProperly
    }

    var body: some View {
        GuidePage(content: {
            VStack {
                LeadingImage("Cannula Inserted")
            
                HStack {
                    FrameworkLocalText("Is the cannula inserted properly?", comment: "Question to confirm the cannula is inserted properly").bold()
                    Spacer()
                }
                HStack {
                    FrameworkLocalText("The window on the top of the Pod should be colored pink when the cannula is properly inserted into the skin.", comment: "Description of proper cannula insertion").fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }.padding(.vertical)
            }

        }) {
            VStack(spacing: 10) {
                Button(action: {
                    self.wasInsertedProperly()
                }) {
                    Text(LocalizedString("Yes", comment: "Button label for user to answer cannula was properly inserted"))
                        .actionButtonStyle(.primary)
                }
                Button(action: {
                    self.didRequestDeactivation()
                }) {
                    Text(LocalizedString("No", comment: "Button label for user to answer cannula was not properly inserted"))
                        .actionButtonStyle(.destructive)
                }
            }.padding()
        }
        .animation(.default)
        .alert(isPresented: $cancelModalIsPresented) { cancelPairingModal }
        .navigationBarTitle(LocalizedString("Check Cannula", comment: "navigation bar title for check cannula"), displayMode: .automatic)
        .navigationBarItems(trailing: cancelButton)
        .navigationBarBackButtonHidden(true)
    }
    
    var cancelButton: some View {
        Button(LocalizedString("Cancel", comment: "Cancel button text in navigation bar on insert cannula screen")) {
            cancelModalIsPresented = true
        }
        .accessibility(identifier: "button_cancel")
    }

    var cancelPairingModal: Alert {
        return Alert(
            title: FrameworkLocalText("Are you sure you want to cancel Pod setup?", comment: "Alert title for cancel pairing modal"),
            message: FrameworkLocalText("If you cancel Pod setup, the current Pod will be deactivated and will be unusable.", comment: "Alert message body for confirm pod attachment"),
            primaryButton: .destructive(FrameworkLocalText("Yes, Deactivate Pod", comment: "Button title for confirm deactivation option"), action: { didRequestDeactivation() } ),
            secondaryButton: .default(FrameworkLocalText("No, Continue With Pod", comment: "Continue pairing button title of in pairing cancel modal"))
        )
    }

}

struct CheckInsertedCannulaView_Previews: PreviewProvider {
    static var previews: some View {
        CheckInsertedCannulaView(didRequestDeactivation: {}, wasInsertedProperly: {} )
    }
}
