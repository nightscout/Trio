//
//  PodSetupView.swift
//  OmniKit
//
//  Created by Pete Schwamb on 5/17/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct PodSetupView: View {
    @Environment(\.dismissAction) private var dismiss
    
    private struct AlertIdentifier: Identifiable {
        enum Choice {
            case skipOnboarding
        }
        var id: Choice
    }
    @State private var alertIdentifier: AlertIdentifier?

    let nextAction: () -> Void
    let allowDebugFeatures: Bool
    let skipOnboarding: () -> Void
    
    var body: some View {
        VStack(alignment: .leading) {
            close
            ScrollView {
                content
            }
            Spacer()
            continueButton
                .padding(.bottom)
        }
        .padding(.horizontal)
        .navigationBarHidden(true)
        .alert(item: $alertIdentifier) { alert in
            switch alert.id {
            case .skipOnboarding:
                return skipOnboardingAlert
            }
        }
    }
    
    @ViewBuilder
    private var close: some View {
        HStack {
            Spacer()
            cancelButton
        }
        .padding(.top)
    }
        
    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .padding(.top, 5)
                .onLongPressGesture(minimumDuration: 2) {
                    didLongPressOnTitle()
                }
            Divider()
            bodyText
                .foregroundColor(.secondary)
                .padding(.top)
        }
    }

    @ViewBuilder
    private var title: some View {
        Text(LocalizedString("Pod Setup", comment: "Title for PodSetupView"))
            .font(.largeTitle)
            .bold()
            .padding(.vertical)
    }
    
    @ViewBuilder
    private var bodyText: some View {
        Text(LocalizedString("You will now begin the process of configuring your reminders, filling your Pod with insulin, pairing to your device and placing it on your body.", comment: "bodyText for PodSetupView"))
    }
    
    private var cancelButton: some View {
        Button(LocalizedString("Cancel", comment: "Cancel button title"), action: {
            self.dismiss()
        })
    }

    private var continueButton: some View {
        Button(LocalizedString("Continue", comment: "Text for continue button on PodSetupView"), action: nextAction)
            .buttonStyle(ActionButtonStyle())
    }
    
    private var skipOnboardingAlert: Alert {
        Alert(title: Text("Skip Omnipod Onboarding?"),
              message: Text("Are you sure you want to skip Omnipod Onboarding?"),
              primaryButton: .cancel(),
              secondaryButton: .destructive(Text("Yes"), action: skipOnboarding))
    }
    
    private func didLongPressOnTitle() {
        if allowDebugFeatures {
            alertIdentifier = AlertIdentifier(id: .skipOnboarding)
        }
    }

}

struct PodSetupView_Previews: PreviewProvider {
    static var previews: some View {
        PodSetupView(nextAction: {}, allowDebugFeatures: true, skipOnboarding: {})
    }
}
