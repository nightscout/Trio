import Foundation
import SwiftUI
import WidgetKit

struct LiveActivityBGLabelLargeView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    var additionalState: LiveActivityAttributes.ContentAdditionalState
    var glucoseColor: Color

    var body: some View {
        HStack(alignment: .center) {
            if let trendArrow = context.state.direction {
                Text(context.state.bg)
                    .fontWeight(.bold)
                    .font(.title)
                    .foregroundStyle(context.isStale ? .secondary : glucoseColor)
                    .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))

                Text(trendArrow)
                    .foregroundStyle(context.isStale ? .secondary : glucoseColor)
                    .fontWeight(.bold)
                    .font(.headline)
            } else {
                Text(context.state.bg)
                    .fontWeight(.bold)
                    .font(.title)
                    .foregroundStyle(context.isStale ? .secondary : glucoseColor)
                    .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
            }
        }
    }
}
