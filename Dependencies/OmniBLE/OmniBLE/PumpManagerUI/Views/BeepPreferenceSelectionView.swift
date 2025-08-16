//
//  BeepPreferenceSelectionView.swift
//  OmniBLE
//
//  Created by Pete Schwamb on 2/14/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI

struct BeepPreferenceSelectionView: View {

    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    private var initialValue: BeepPreference
    @State private var preference: BeepPreference
    private var onSave: ((_ selectedValue: BeepPreference, _ completion: @escaping (_ error: LocalizedError?) -> Void) -> Void)?

    @State private var alertIsPresented: Bool = false
    @State private var error: LocalizedError?
    @State private var saving: Bool = false


    init(initialValue: BeepPreference, onSave: @escaping (_ selectedValue: BeepPreference, _ completion: @escaping (_ error: LocalizedError?) -> Void) -> Void) {
        self.initialValue = initialValue
        self._preference = State(initialValue: initialValue)
        self.onSave = onSave
    }

    var body: some View {
        contentWithCancel
    }

    var content: some View {
        VStack {
            List {
                Section {
                    Text(LocalizedString("Confidence reminders are beeps from the Pod which can be used to acknowledge selected commands when the Pod is not silenced.", comment: "Help text for BeepPreferenceSelectionView")).fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 10)
                }

                Section {
                    ForEach(BeepPreference.allCases, id: \.self) { preference in
                        HStack {
                            CheckmarkListItem(
                                title: Text(preference.title),
                                description: Text(preference.description),
                                isSelected: Binding(
                                    get: { self.preference == preference },
                                    set: { isSelected in
                                        if isSelected {
                                            self.preference = preference
                                        }
                                    }
                                )
                            )
                        }
                        .padding(.vertical, 10)
                    }
                }
                .buttonStyle(PlainButtonStyle()) // Disable row highlighting on selection
            }
            VStack {
                Button(action: {
                    saving = true
                    onSave?(preference) { (error) in
                        saving = false
                        if let error = error {
                            self.error = error
                            self.alertIsPresented = true
                        } else {
                            self.presentationMode.wrappedValue.dismiss()
                        }
                    }
                }) {
                    Text(saveButtonText)
                        .actionButtonStyle(.primary)
                }
                .padding()
                .disabled(saving || !valueChanged)
            }
            .padding(self.horizontalSizeClass == .regular ? .bottom : [])
            .background(Color(UIColor.secondarySystemGroupedBackground).shadow(radius: 5))

        }
        .insetGroupedListStyle()
        .navigationTitle(LocalizedString("Confidence Reminders", comment: "navigation title for confidence reminders"))
         .navigationBarTitleDisplayMode(.automatic)
        .alert(isPresented: $alertIsPresented, content: { alert(error: error) })
    }

    private var contentWithCancel: some View {
        if saving {
            return AnyView(content
                .navigationBarBackButtonHidden(true)
            )
        } else if valueChanged {
            return AnyView(content
                .navigationBarBackButtonHidden(true)
                .navigationBarItems(leading: cancelButton)
            )
        } else {
            return AnyView(content)
        }
    }

    private var cancelButton: some View {
        Button(action: { self.presentationMode.wrappedValue.dismiss() } ) {
            Text(LocalizedString("Cancel", comment: "Button title for cancelling confidence reminders edit"))
        }
    }

    var saveButtonText: String {
        if saving {
            return LocalizedString("Saving...", comment: "button title for saving confidence reminder while saving")
        } else {
            return LocalizedString("Save", comment: "button title for saving confidence reminder")
        }
    }

    private var valueChanged: Bool {
        return preference != initialValue
    }

    private func alert(error: Error?) -> SwiftUI.Alert {
        return SwiftUI.Alert(
            title: Text(LocalizedString("Failed to update confidence reminder preference.", comment: "Alert title for error when updating confidence reminder preference")),
            message: Text(error?.localizedDescription ?? "No Error")
        )
    }

}

struct BeepPreferenceSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            BeepPreferenceSelectionView(initialValue: .extended) { selectedValue, completion in
                print("Selected: \(selectedValue)")
                completion(nil)
            }
        }
    }
}
