//
// Trio
// LiveActivityCOBLabelView.swift
// Created by Deniz Cengiz on 2024-10-17.
// Last edited by Deniz Cengiz on 2025-02-21.
// Most contributions by Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import Foundation
import SwiftUI
import WidgetKit

struct LiveActivityCOBLabelView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    var additionalState: LiveActivityAttributes.ContentAdditionalState

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(
                    "\(additionalState.cob)"
                ).fontWeight(.bold)
                    .font(.title3)
                    .foregroundStyle(context.isStale ? .secondary : .primary)
                    .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))

                Text(String(localized: "g", comment: "gram of carbs"))
                    .font(.headline).fontWeight(.bold)
                    .foregroundStyle(context.isStale ? .secondary : .primary)
                    .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
            }
            Text("COB").font(.subheadline).foregroundStyle(.primary)
        }
    }
}
