//
//  LiveActivityGlucoseDeltaLabelView.swift
//  Trio
//
//  Created by Cengiz Deniz on 17.10.24.
//
import Foundation
import SwiftUI
import WidgetKit

struct LiveActivityGlucoseDeltaLabelView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    /// Color to render the delta in. Callers resolve this, so that each layout can decide whether the delta
    /// follows Trio's glucose color scheme or stays in the default text color.
    var glucoseColor: Color

    var body: some View {
        if !context.state.change.isEmpty {
            Text(context.state.change)
                .foregroundStyle(context.isStale ? .secondary : glucoseColor)
                .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
        } else {
            Text("--")
        }
    }
}
