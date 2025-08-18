//
//  InsulinTypeConfirmation.swift
//  MockKitUI
//
//  Created by Pete Schwamb on 1/1/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI

struct InsulinTypeConfirmation: View {
    
    @State private var insulinType: InsulinType?
    private var supportedInsulinTypes: [InsulinType]
    private var didConfirm: (InsulinType) -> Void
    private var didCancel: () -> Void
    
    init(initialValue: InsulinType, supportedInsulinTypes: [InsulinType], didConfirm: @escaping (InsulinType) -> Void, didCancel: @escaping () -> Void) {
        self._insulinType = State(initialValue: initialValue)
        self.supportedInsulinTypes = supportedInsulinTypes
        self.didConfirm = didConfirm
        self.didCancel = didCancel
    }
    
    func continueWithType(_ insulinType: InsulinType?) {
        if let insulinType = insulinType {
            didConfirm(insulinType)
        } else {
            assertionFailure()
        }
    }
    
    var body: some View {
        VStack {
            List {
                Section {
                    Text(LocalizedString("Select the type of insulin that you will be using in this pod.", comment: "Title text for insulin type confirmation page"))
                }
                Section {
                    InsulinTypeChooser(insulinType: $insulinType, supportedInsulinTypes: supportedInsulinTypes)
                }
                .buttonStyle(PlainButtonStyle()) // Disable row highlighting on selection
            }
            .insetGroupedListStyle()
            
            Button(action: { self.continueWithType(insulinType) }) {
                Text(LocalizedString("Continue", comment: "Text for continue button"))
                    .actionButtonStyle(.primary)
                    .padding()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(LocalizedString("Cancel", comment: "Cancel button title"), action: {
                    didCancel()
                })
            }
        }
    }
}

struct InsulinTypeConfirmation_Previews: PreviewProvider {
    static var previews: some View {
        InsulinTypeConfirmation(initialValue: .humalog, supportedInsulinTypes: InsulinType.allCases, didConfirm: { (newType) in }, didCancel: { })
    }
}
