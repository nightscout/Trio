//
// Trio
// LiveActivityUpdatedLabelView.swift
// Created by Deniz Cengiz on 2024-10-17.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Deniz Cengiz and Andreas Stokholm.
//
// Documentation available under: https://triodocs.org/

import Foundation
import SwiftUI
import WidgetKit

struct LiveActivityUpdatedLabelView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    var isDetailedLayout: Bool

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        let dateText = Text("\((context.state.date != nil) ? dateFormatter.string(from: context.state.date!) : "--")")

        if isDetailedLayout {
            VStack {
                dateText
                    .font(.title3)
                    .bold()
                    .foregroundStyle(context.isStale ? .red.opacity(0.6) : .primary)
                    .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))

                Text("Updated").font(.subheadline).foregroundStyle(.primary)
            }
        } else {
            HStack {
                Text("Updated:").font(.subheadline).foregroundStyle(.secondary)

                dateText
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(context.isStale ? .red.opacity(0.6) : .secondary)
                    .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
            }
        }
    }
}
