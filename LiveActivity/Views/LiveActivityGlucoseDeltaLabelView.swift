// Trio
// LiveActivityGlucoseDeltaLabelView.swift
// Created by Deniz Cengiz on 2024-10-17.

import Foundation
import SwiftUI
import WidgetKit

struct LiveActivityGlucoseDeltaLabelView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    var glucoseColor: Color

    var body: some View {
        if !context.state.change.isEmpty {
            Text(context.state.change)
                .foregroundStyle(context.state.glucoseColorScheme == "staticColor" ? .primary : glucoseColor)
                .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
        } else {
            Text("--")
        }
    }
}
