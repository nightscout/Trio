//
//  SilencePodSelectionView.swift
//  OmniBLE
//
//  Created by Joe Moran 8/30/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI

struct SilencePodSelectionView: View {

    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    private var initialValue: SilencePodPreference
    @State private var preference: SilencePodPreference
    private var onSave: ((_ selectedValue: SilencePodPreference, _ completion: @escaping (_ error: LocalizedError?) -> Void) -> Void)?

    @State private var alertIsPresented: Bool = false
    @State private var error: LocalizedError?
    @State private var saving: Bool = false


    init(initialValue: SilencePodPreference, onSave: @escaping (_ selectedValue: SilencePodPreference, _ completion: @escaping (_ error: LocalizedError?) -> Void) -> Void) {
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
                    Text(LocalizedString("Silence Pod mode suppresses all Pod alert and confirmation reminder beeping.", comment: "Help text for Silence Pod view")).fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 10)
                }
                Section {
                    ForEach(SilencePodPreference.allCases, id: \.self) { preference in
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
        .navigationTitle(LocalizedString("Silence Pod", comment: "navigation title for Silnce Pod"))
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
            Text(LocalizedString("Cancel", comment: "Button title for cancelling silence pod edit"))
        }
    }

    var saveButtonText: String {
        if saving {
            return LocalizedString("Saving...", comment: "button title for saving silence pod preference while saving")
        } else {
            return LocalizedString("Save", comment: "button title for saving silence pod preference")
        }
    }

    private var valueChanged: Bool {
        return preference != initialValue
    }

    private func alert(error: Error?) -> SwiftUI.Alert {
        return SwiftUI.Alert(
            title: Text(LocalizedString("Failed to update silence pod preference.", comment: "Alert title for error when updating silence pod preference")),
            message: Text(error?.localizedDescription ?? "No Error")
        )
    }
}

struct SilencePodSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SilencePodSelectionView(initialValue: .disabled) { selectedValue, completion in
                print("Selected: \(selectedValue)")
                completion(nil)
            }
        }
    }
}
