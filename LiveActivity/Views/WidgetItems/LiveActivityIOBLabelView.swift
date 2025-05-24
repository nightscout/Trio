//
// Trio
// LiveActivityIOBLabelView.swift
// Created by Deniz Cengiz on 2024-10-17.
// Last edited by Deniz Cengiz on 2025-02-21.
// Most contributions by Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import Foundation
import SwiftUI
import WidgetKit

struct LiveActivityIOBLabelView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    var additionalState: LiveActivityAttributes.ContentAdditionalState

    private var bolusFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(
                    bolusFormatter.string(from: additionalState.iob as NSNumber) ?? "--"
                )
                .fontWeight(.bold)
                .font(.title3)
                .foregroundStyle(context.isStale ? .secondary : .primary)
                .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))

                Text(String(localized: "U", comment: "Insulin unit"))
                    .font(.headline).fontWeight(.bold)
                    .foregroundStyle(context.isStale ? .secondary : .primary)
                    .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
            }
            Text("IOB").font(.subheadline).foregroundStyle(.primary)
        }
    }
}
