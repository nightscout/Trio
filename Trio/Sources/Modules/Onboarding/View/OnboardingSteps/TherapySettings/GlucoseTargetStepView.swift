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
    @State private var therapyItems: [TherapySettingItem] = []
    @Namespace private var bottomID

    var body: some View {
        ScrollViewReader { proxy in
            LazyVStack {
                TherapySettingEditorView(
                    items: $therapyItems,
                    unit: state.units == .mgdL ? .mgdL : .mmolL,
                    timeOptions: state.targetTimeValues,
                    valueOptions: state.targetRateValues,
                    validateOnDelete: state.validateTarget,
                    onItemAdded: {
                        withAnimation {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                    },
                    chartColor: Color.green,
                    chartDisplayValueSelector: { state.units == .mgdL ? $0.value : $0.value.asMmolL },
                    chartShowsArea: false,
                    chartYScale: (state.units == .mgdL ? Decimal(72) : Decimal(72).asMmolL) ...
                        (state.units == .mgdL ? Decimal(180) : Decimal(180).asMmolL)
                ).id(bottomID)
            }
            .onAppear {
                if state.targetItems.isEmpty {
                    state.addInitialTarget()
                }
                state.validateTarget()
                therapyItems = state.getTargetTherapyItems()
            }.onChange(of: therapyItems) { _, newItems in
                state.updateTargets(from: newItems)
            }
        }
    }
}
