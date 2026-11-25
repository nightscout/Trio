import SwiftUI
import WidgetKit

struct LiveActivityBGLabelWatchView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    var glucoseColor: Color

    var body: some View {
        // No stack on purpose: the texts must be direct children of the row's HStack in LiveActivityView,
        // a nested stack changes how that row divides its width. Only place inside an HStack, without modifiers.
        Group {
            Text(context.state.bg)
                .font(.callout)
                .fontWeight(.bold)
                .foregroundStyle(context.isStale ? .secondary : glucoseColor)
                .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            if let trendArrow = context.state.direction {
                Text(trendArrow)
                    .font(.callout)
                    .fontWeight(.bold)
                    .foregroundStyle(context.isStale ? .secondary : glucoseColor)
                    .padding(.leading, -5)
            }

            Text(context.state.change)
                .font(.callout)
                .foregroundStyle(context.isStale ? .secondary : glucoseColor)
                .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }
}
