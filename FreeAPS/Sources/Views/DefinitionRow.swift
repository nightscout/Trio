import Foundation
import SwiftUI

struct DefinitionRow: View {
    var term: String
    var definition: String
    var color: Color?
    var fontSize: Font?

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                if let color = color {
                    Image(systemName: "circle.fill").foregroundStyle(color)
                }
                Text(term).font(fontSize ?? .subheadline).fontWeight(.semibold)
            }.padding(.bottom, 5)
            Text(definition)
                .font(fontSize ?? .subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 5)
    }
}
