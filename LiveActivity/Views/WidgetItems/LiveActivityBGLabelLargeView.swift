import Foundation
import SwiftUI
import WidgetKit

struct LiveActivityBGLabelLargeView: View {
    @Environment(\.isWatchOS) var isWatchOS

    var context: ActivityViewContext<LiveActivityAttributes>
    var glucoseColor: Color
    var glucoseFont: Font? = nil
    var arrowFont: Font? = nil

    var body: some View {
        HStack(alignment: .center) {
            Text(context.state.bg)
                .fontWeight(.bold)
                .font(glucoseFont ?? (!isWatchOS ? .title : .title3))
                .foregroundStyle(context.isStale ? .secondary : glucoseColor)
                .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))

            if let trendArrow = context.state.direction {
                Text(trendArrow)
                    .foregroundStyle(context.isStale ? .secondary : glucoseColor)
                    .fontWeight(.bold)
                    .font(arrowFont ?? (!isWatchOS ? .headline : .subheadline))
                    .padding(.leading, !isWatchOS ? 0 : -5)
            }
        }
    }
}
