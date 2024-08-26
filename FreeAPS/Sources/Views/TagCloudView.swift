import Combine
import Foundation
import SwiftUI
import Swinject

struct TagCloudView: View {
    var tags: [String]
    var shouldParseToMmolL: Bool

    @State private var totalHeight
//          = CGFloat.zero       // << variant for ScrollView/List
        = CGFloat.infinity // << variant for VStack
    var body: some View {
        VStack {
            GeometryReader { geometry in
                self.generateContent(in: geometry)
            }
        }
//        .frame(height: totalHeight)// << variant for ScrollView/List
        .frame(maxHeight: totalHeight) // << variant for VStack
    }

    private func generateContent(in g: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero

        return ZStack(alignment: .topLeading) {
            ForEach(self.tags, id: \.self) { tag in
                self.item(for: tag, isMmolL: shouldParseToMmolL)
                    .padding([.horizontal, .vertical], 2)
                    .alignmentGuide(.leading, computeValue: { d in
                        if abs(width - d.width) > g.size.width
                        {
                            width = 0
                            height -= d.height
                        }
                        let result = width
                        if tag == self.tags.last! {
                            width = 0 // last item
                        } else {
                            width -= d.width
                        }
                        return result
                    })
                    .alignmentGuide(.top, computeValue: { _ in
                        let result = height
                        if tag == self.tags.last! {
                            height = 0 // last item
                        }
                        return result
                    })
            }
        }.background(viewHeightReader($totalHeight))
    }

//    private func item(for textTag: String) -> some View {
//        var colorOfTag: Color {
//            switch textTag {
//            case textTag where textTag.contains("SMB Delivery Ratio:"):
//                return .uam
//            case textTag where textTag.contains("Bolus"):
//                return .green
//            case textTag where textTag.contains("TDD:"),
//                 textTag where textTag.contains("tdd_factor"),
//                 textTag where textTag.contains("Sigmoid function"),
//                 textTag where textTag.contains("Logarithmic formula"),
//                 textTag where textTag.contains("AF:"),
//                 textTag where textTag.contains("Autosens/Dynamic Limit:"),
//                 textTag where textTag.contains("Dynamic ISF/CR"),
//                 textTag where textTag.contains("Basal ratio"),
//                 textTag where textTag.contains("SMB Ratio"):
//                return .zt
//            case textTag where textTag.contains("Middleware:"):
//                return .red
//            case textTag where textTag.contains("SMB Ratio"):
//                return .orange
//            default:
//                return .insulin
//            }
//        }
//
//        return ZStack { Text(textTag)
//            .padding(.vertical, 2)
//            .padding(.horizontal, 4)
//            .font(.subheadline)
//            .background(colorOfTag.opacity(0.8))
//            .foregroundColor(Color.white)
//            .cornerRadius(2) }
//    }
    private func item(for textTag: String, isMmolL: Bool) -> some View {
        var colorOfTag: Color {
            switch textTag {
            case textTag where textTag.contains("SMB Delivery Ratio:"):
                return .uam
            case textTag where textTag.contains("Bolus"):
                return .green
            case textTag where textTag.contains("TDD:"),
                 textTag where textTag.contains("tdd_factor"),
                 textTag where textTag.contains("Sigmoid function"),
                 textTag where textTag.contains("Logarithmic formula"),
                 textTag where textTag.contains("AF:"),
                 textTag where textTag.contains("Autosens/Dynamic Limit:"),
                 textTag where textTag.contains("Dynamic ISF/CR"),
                 textTag where textTag.contains("Basal ratio"),
                 textTag where textTag.contains("SMB Ratio"):
                return .zt
            case textTag where textTag.contains("Middleware:"):
                return .red
            case textTag where textTag.contains("SMB Ratio"):
                return .orange
            default:
                return .insulin
            }
        }

        func formattedTextTag(for tag: String) -> String {
            // List of glucose-related tags
            let glucoseTags = ["ISF:", "Target:", "minPredBG", "minGuardBG", "IOBpredBG", "COBpredBG", "UAMpredBG", "Dev:"]

            var updatedTag = tag

            // Apply conversion if necessary
            for glucoseTag in glucoseTags {
                if glucoseTag == "ISF:" {
                    // Handle the special ISF case with the arrow
                    if let range = updatedTag.range(of: "\(glucoseTag)\\s*\\d+→\\d+", options: .regularExpression) {
                        let glucoseValueString = updatedTag[range]
                        let values = glucoseValueString.components(separatedBy: "→")

                        if let firstValue = Double(
                            values[0]
                                .components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                        ),
                            let secondValue = Double(
                                values[1]
                                    .components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                            )
                        {
                            let formattedFirstValue = isMmolL ? Double(firstValue.asMmolL) : firstValue
                            let formattedSecondValue = isMmolL ? Double(secondValue.asMmolL) : secondValue

                            let formattedGlucoseValueString =
                                "\(glucoseTag) \(formattedFirstValue)→\(formattedSecondValue)"
                            updatedTag = updatedTag.replacingOccurrences(
                                of: glucoseValueString,
                                with: formattedGlucoseValueString
                            )
                        }
                    }
                } else {
                    // General case for other glucose tags
                    if let range = updatedTag.range(of: "\(glucoseTag)\\s*\\d+", options: .regularExpression) {
                        let glucoseValueString = updatedTag[range]
                        if let glucoseValue = Double(
                            glucoseValueString
                                .components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                        ) {
                            let formattedValue = isMmolL ? Double(glucoseValue.asMmolL) : glucoseValue
                            updatedTag = updatedTag.replacingOccurrences(
                                of: glucoseValueString,
                                with: "\(glucoseTag) \(formattedValue)"
                            )
                        }
                    }
                }
            }
            return updatedTag
        }

        let formattedTextTag = formattedTextTag(for: textTag)

        return ZStack {
            Text(formattedTextTag)
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .font(.subheadline)
                .background(colorOfTag.opacity(0.8))
                .foregroundColor(Color.white)
                .cornerRadius(2)
        }
    }

    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        GeometryReader { geometry -> Color in
            let rect = geometry.frame(in: .local)
            DispatchQueue.main.async {
                binding.wrappedValue = rect.size.height
            }
            return .clear
        }
    }
}

struct TestTagCloudView: View {
    var body: some View {
        VStack {
            Text("Header").font(.largeTitle)
            TagCloudView(
                tags: ["Ninetendo", "XBox", "PlayStation", "PlayStation 2", "PlayStation 3", "PlayStation 4"],
                shouldParseToMmolL: false
            )
            Text("Some other text")
            Divider()
            Text("Some other cloud")
            TagCloudView(tags: ["Apple", "Google", "Amazon", "Microsoft", "Oracle", "Facebook"], shouldParseToMmolL: false)
        }
    }
}
