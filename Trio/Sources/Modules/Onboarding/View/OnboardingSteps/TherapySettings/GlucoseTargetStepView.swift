//
//  GlucoseTargetStepView.swift
//  Trio
//
//  Created by Marvin Polscheit on 19.03.25.
//
import Charts
import Foundation
import SwiftUI
import UIKit

/// Glucose target step view for setting target glucose range.
struct GlucoseTargetStepView: View {
    @Bindable var state: Onboarding.StateModel
    @Namespace private var bottomID

    var body: some View {
        ScrollViewReader { proxy in
            LazyVStack {
                TherapySettingsEditor.EditingView(
                    therapyType: .bloodGlucoseTarget,
                    items: $state.targetItems,
                    unit: state.units == .mgdL ? .mgdL : .mmolL,
                    timeOptions: state.targetTimeValues,
                    valueOptions: state.targetRateValues,
                    validateOnDelete: state.validateTarget,
                    onItemAdded: {
                        withAnimation {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                    }
                ).id(bottomID)
            }
            .onAppear {
                if state.targetItems.isEmpty {
                    state.addInitialTarget()
                }
                state.validateTarget()
            }
        }
    }
}
