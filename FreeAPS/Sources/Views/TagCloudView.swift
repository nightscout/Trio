import Combine
import Foundation
import SwiftUI
import Swinject

struct TagCloudView: View {
    var tags: [String]
    var shouldParseToMmolL: Bool

    @State private var totalHeight = CGFloat.infinity // << variant for VStack

    var body: some View {
        VStack {
            GeometryReader { geometry in
                self.generateContent(in: geometry)
            }
        }
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
                        if abs(width - d.width) > g.size.width {
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

        let formattedTextTag = formatGlucoseTags(textTag, isMmolL: isMmolL)

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

    /**
     Converts glucose-related values in the given `tag` string to mmol/L, including ranges (e.g., `ISF: 54→54`), comparisons (e.g., `maxDelta 37 > 20% of BG 95`), and both positive and negative values (e.g., `Dev: -36`).

     - Parameters:
       - tag: The string containing glucose-related values to be converted.
       - isMmolL: A Boolean flag indicating whether to convert values to mmol/L.

     - Returns:
       A string with glucose values converted to mmol/L.

     - Glucose tags handled: `ISF:`, `Target:`, `minPredBG`, `minGuardBG`, `IOBpredBG`, `COBpredBG`, `UAMpredBG`, `Dev:`, `maxDelta`, `BG`.
     */
    private func formatGlucoseTags(_ tag: String, isMmolL: Bool) -> String {
        // Updated pattern to handle cases like minGuardBG 34, minGuardBG 34<70, "maxDelta 37 > 20% of BG 95", and ensure "Target:" is handled correctly
        let pattern =
            "(ISF:\\s*-?\\d+→-?\\d+|Dev:\\s*-?\\d+|Target:\\s*-?\\d+|(?:minPredBG|minGuardBG|IOBpredBG|COBpredBG|UAMpredBG|maxDelta|BG)\\s*-?\\d+(?:<\\d+)?(?:>\\s*\\d+%\\s*of\\s*BG\\s*\\d+)?)"

        let regex = try! NSRegularExpression(pattern: pattern)

        func convertToMmolL(_ value: String) -> String {
            if let glucoseValue = Double(value.replacingOccurrences(of: "[^\\d.-]", with: "", options: .regularExpression)) {
                return isMmolL ? glucoseValue.asMmolL.description : value
            }
            return value
        }

        let matches = regex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag))
        var updatedTag = tag

        for match in matches.reversed() {
            if let range = Range(match.range, in: tag) {
                let glucoseValueString = String(tag[range])

                if glucoseValueString.contains("→") {
                    // Handle ISF case with an arrow (e.g., ISF: 54→54)
                    let values = glucoseValueString.components(separatedBy: "→")
                    let firstValue = convertToMmolL(values[0])
                    let secondValue = convertToMmolL(values[1])
                    let formattedGlucoseValueString = "\(values[0].components(separatedBy: ":")[0]): \(firstValue)→\(secondValue)"
                    updatedTag.replaceSubrange(range, with: formattedGlucoseValueString)
                } else if glucoseValueString.contains("<") {
                    // Handle range case for minGuardBG like "minGuardBG 34<70"
                    let values = glucoseValueString.components(separatedBy: "<")
                    let firstValue = convertToMmolL(values[0])
                    let secondValue = convertToMmolL(values[1])
                    let formattedGlucoseValueString = "\(values[0].components(separatedBy: ":")[0]) \(firstValue)<\(secondValue)"
                    updatedTag.replaceSubrange(range, with: formattedGlucoseValueString)
                } else if glucoseValueString.contains(">"), glucoseValueString.contains("BG") {
                    // Handle cases like "maxDelta 37 > 20% of BG 95"
                    let pattern = "(\\d+) > \\d+% of BG (\\d+)"
                    let matches = try! NSRegularExpression(pattern: pattern)
                        .matches(in: glucoseValueString, range: NSRange(glucoseValueString.startIndex..., in: glucoseValueString))

                    if let match = matches.first, match.numberOfRanges == 3 {
                        let firstValueRange = Range(match.range(at: 1), in: glucoseValueString)!
                        let secondValueRange = Range(match.range(at: 2), in: glucoseValueString)!

                        let firstValue = convertToMmolL(String(glucoseValueString[firstValueRange]))
                        let secondValue = convertToMmolL(String(glucoseValueString[secondValueRange]))

                        let formattedGlucoseValueString = glucoseValueString.replacingOccurrences(
                            of: "\(glucoseValueString[firstValueRange]) > 20% of BG \(glucoseValueString[secondValueRange])",
                            with: "\(firstValue) > 20% of BG \(secondValue)"
                        )
                        updatedTag.replaceSubrange(range, with: formattedGlucoseValueString)
                    }
                } else {
                    // General case for single glucose values like "Target: 100" or "minGuardBG 34"
                    let parts = glucoseValueString.components(separatedBy: CharacterSet(charactersIn: ": "))
                    let formattedValue = convertToMmolL(parts.last!.trimmingCharacters(in: .whitespaces))
                    updatedTag.replaceSubrange(range, with: "\(parts[0]): \(formattedValue)")
                }
            }
        }

        return updatedTag
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
