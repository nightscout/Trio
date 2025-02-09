import Foundation
import SwiftUI

struct DefinitionRow<DefinitionView: View>: View {
    var term: String
    var definition: DefinitionView
    var color: Color?
    var fontSize: Font?
    var iconString: String?
    var shouldRotateIcon: Bool?

    init(
        term: String,
        definition: DefinitionView,
        color: Color? = nil,
        fontSize: Font? = nil,
        iconString: String? = nil,
        shouldRotateIcon: Bool = false
    ) {
        self.term = term
        self.definition = definition
        self.color = color
        self.fontSize = fontSize
        self.iconString = iconString
        self.shouldRotateIcon = shouldRotateIcon
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                if let color = color {
                    if let iconString = iconString {
                        Image(systemName: iconString)
                            .foregroundStyle(color)
                            .rotationEffect(shouldRotateIcon == true ? .degrees(180) : .degrees(0))
                    } else {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(color)
                    }
                }
                Text(term).font(fontSize ?? .subheadline).fontWeight(.semibold)
            }.padding(.bottom, 5)
            definition
                .font(fontSize ?? .subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 5)
    }
}
