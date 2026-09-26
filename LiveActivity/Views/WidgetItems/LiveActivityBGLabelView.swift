import Foundation
import SwiftUI
import WidgetKit

struct LiveActivityBGLabelView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    var additionalState: LiveActivityAttributes.ContentAdditionalState
    var glucoseColor: Color = .primary

    var body: some View {
        Text(context.state.bg)
            .fontWeight(.bold)
            .font(.title3)
            .foregroundStyle(context.isStale ? .secondary : glucoseColor)
            .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
    }
}
