//
//  G7StartupView.swift
//  CGMBLEKitUI
//
//  Created by Pete Schwamb on 9/24/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI

struct G7StartupView: View {
    var didContinue: (() -> Void)?
    var didCancel: (() -> Void)?

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Spacer()
            Text(LocalizedString("Dexcom G7", comment: "Title on WelcomeView"))
                .font(.largeTitle)
                .fontWeight(.semibold)
            VStack(alignment: .center) {
                Image(frameworkImage: "g7")
                    .resizable()
                    .aspectRatio(contentMode: ContentMode.fit)
                    .frame(height: 120)
                    .padding(.horizontal)
            }.frame(maxWidth: .infinity)
            Text(LocalizedString("iAPS can read G7 CGM data, but you must still use the Dexcom G7 App for pairing, calibration, and other sensor management.", comment: "Descriptive text on G7StartupView"))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(.secondary)
            Spacer()
            Button(action: { self.didContinue?() }) {
                Text(LocalizedString("Continue", comment:"Button title for starting setup"))
                    .actionButtonStyle(.primary)
            }
            Button(action: { self.didCancel?() } ) {
                Text(LocalizedString("Cancel", comment: "Button text to cancel G7 setup")).padding(.top, 20)
            }
        }
        .padding()
        .environment(\.horizontalSizeClass, .compact)
        .navigationBarTitle("")
        .navigationBarHidden(true)
    }
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            G7StartupView()
        }
        .previewDevice("iPod touch (7th generation)")
    }
}
