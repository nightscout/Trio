import Foundation
import SwiftUI

struct DefinitionRow: View {
    var term: String
    var definition: String
    var color: Color?

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                if let color = color {
                    Image(systemName: "circle.fill").foregroundStyle(color)
                }
                Text(term).font(.subheadline).fontWeight(.semibold)
            }
            Text(definition)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 5)
    }
}
