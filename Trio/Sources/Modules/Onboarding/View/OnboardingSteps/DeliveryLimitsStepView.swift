//
//  DeliveryLimitsStepView.swift
//  Trio
//
//  Created by Cengiz Deniz on 02.04.25.
//

import SwiftUI

struct DeliveryLimitsStepView: View {
    @Bindable var state: Onboarding.StateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Max IOB")
            Text("Max Bolus")
            Text("Max Basal")
            Text("Max COB")
        }
    }
}
