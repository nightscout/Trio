//
//  UncertaintyRecoveredView.swift
//  OmniKit
//
//  Created by Pete Schwamb on 8/25/20.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct UncertaintyRecoveredView: View {
    var appName: String
    
    var didFinish: (() -> Void)?
    
    var body: some View {
        GuidePage(content: {
            Text(String(format: LocalizedString("%1$@ has recovered communication with the pod on your body.\n\nInsulin delivery records have been updated and should match what has actually been delivered.\n\nYou may continue to use %2$@ normally now.", comment: "Text body for page showing insulin uncertainty has been recovered (1: appName) (2: appName)"), self.appName, self.appName))
               .padding([.top, .bottom])
        }) {
            VStack {
                Button(action: {
                    self.didFinish?()
                }) {
                    Text(LocalizedString("Continue", comment: "Button title to continue"))
                    .actionButtonStyle()
                    .padding()
                }
            }
        }
        .navigationBarTitle(Text("Comms Recovered"), displayMode: .large)
        .navigationBarBackButtonHidden(true)
    }    
}

struct UncertaintyRecoveredView_Previews: PreviewProvider {
    static var previews: some View {
        UncertaintyRecoveredView(appName: "Test App")
    }
}
