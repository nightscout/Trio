//
//  PlayTestBeepsView.swift
//  OmniKit
//
//  Created by Joe Moran on 9/1/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit


struct PlayTestBeepsView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    private var toRun: ((_ completion: @escaping (_ result: Error?) -> Void) -> Void)?

    @State private var alertIsPresented: Bool = false
    @State private var displayString: String = ""
    @State private var successMessage = LocalizedString("Play test beeps command sent successfully.\n\nIf you did not hear any beeps from your Pod, the piezo speaker in your Pod may be broken or disabled.", comment: "Success message for play test beeps")
    @State private var error: Error? = nil
    @State private var executing: Bool = false
    @State private var showActivityView = false

    init(toRun: @escaping (_ completion: @escaping (_ result: Error?) -> Void) -> Void) {
        self.toRun = toRun
    }

    var body: some View {
        VStack {
            List {
                Section {
                    Text(self.displayString).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack {
                Button(action: {
                    asyncAction()
                }) {
                    Text(buttonText)
                        .actionButtonStyle(.primary)
                }
                .padding()
                .disabled(executing)
            }
            .padding(self.horizontalSizeClass == .regular ? .bottom : [])
            .background(Color(UIColor.secondarySystemGroupedBackground).shadow(radius: 5))
        }
        .insetGroupedListStyle()
        .navigationTitle(LocalizedString("Play Test Beeps", comment: "navigation title for play test beeps"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(isPresented: $alertIsPresented, content: { alert(error: error) })
        .onFirstAppear {
            asyncAction()
        }
    }

    private func asyncAction () {
        DispatchQueue.global(qos: .utility).async {
            executing = true
            self.displayString = ""
            toRun?() { (error) in
                if let error = error {
                    self.displayString = ""
                    self.error = error
                    self.alertIsPresented = true
                } else {
                    self.displayString = successMessage
                }
                executing = false
            }
        }
    }

    private var buttonText: String {
        if executing {
            return LocalizedString("Playing Test Beeps...", comment: "button title when executing play test beeps")
        } else {
            return LocalizedString("Play Test Beeps", comment: "button title to play test beeps")
        }
    }

    private func alert(error: Error?) -> SwiftUI.Alert {
        return SwiftUI.Alert(
            title: Text(LocalizedString("Failed to play test beeps.", comment: "Alert title for error when playing test beeps")),
            message: Text(error?.localizedDescription ?? "No Error")
        )
    }
}

struct PlayTestBeepsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PlayTestBeepsView() { completion in
                completion(nil)
            }
        }
    }
}
