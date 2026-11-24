import Foundation
import SwiftUI
import WidgetKit

struct LiveActivityIOBLabelWatchView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    var additionalState: LiveActivityAttributes.ContentAdditionalState
    var glucoseColor: Color

    private var bolusFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }

    var body: some View {
        // No stack on purpose: the texts must be direct children of the row's HStack in LiveActivityView,
        // a nested stack changes how that row divides its width. Only place inside an HStack, without modifiers.
        Group {
            Text(bolusFormatter.string(from: additionalState.iob as NSNumber) ?? "--")
                .font(.callout)
                .foregroundStyle(context.isStale ? .secondary : glucoseColor)
                .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(String(localized: "U", comment: "Insulin unit"))
                .font(.callout)
                .foregroundStyle(context.isStale ? .secondary : glucoseColor)
                .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
        }
    }
}
