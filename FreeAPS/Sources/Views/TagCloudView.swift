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
            case textTag where textTag.contains("Smoothing: On"):
                return .white
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
                .foregroundColor(textTag.contains("Smoothing: On") ? Color.black : Color.white)
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

     - Glucose tags handled: `ISF:`, `Target:`, `minPredBG`, `minGuardBG`, `IOBpredBG`, `COBpredBG`, `UAMpredBG`, `Dev:`, `maxDelta`, `BGI`.
     */

    // TODO: Consolidate all mmol parsing methods (in TagCloudView, NightscoutManager and HomeRootView) to one central func
    private func formatGlucoseTags(_ tag: String, isMmolL: Bool) -> String {
        let patterns = [
            "ISF:\\s*-?\\d+\\.?\\d*→-?\\d+\\.?\\d*",
            "Dev:\\s*-?\\d+\\.?\\d*",
            "BGI:\\s*-?\\d+\\.?\\d*",
            "Target:\\s*-?\\d+\\.?\\d*",
            "(?:minPredBG|minGuardBG|IOBpredBG|COBpredBG|UAMpredBG)\\s*-?\\d+\\.?\\d*"
        ]
        let pattern = patterns.joined(separator: "|")
        let regex = try! NSRegularExpression(pattern: pattern)

        // Convert only if isMmolL == true; otherwise return original mg/dL string
        func convertToMmolL(_ value: String) -> String {
            if let glucoseValue = Double(value.replacingOccurrences(of: "[^\\d.-]", with: "", options: .regularExpression)) {
                let mmolValue = Decimal(glucoseValue).asMmolL // your mg/dL → mmol/L routine
                return isMmolL ? mmolValue.description : value
            }
            return value
        }

        let matches = regex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag))
        var updatedTag = tag

        // Process each match in reverse order
        for match in matches.reversed() {
            guard let range = Range(match.range, in: tag) else { continue }
            let glucoseValueString = String(tag[range])

            if glucoseValueString.contains("→") {
                // -- Handle ISF: X→Y
                let values = glucoseValueString.components(separatedBy: "→")
                // For example "ISF: 162"
                let firstNumber = values[0].components(separatedBy: ":")[1].trimmingCharacters(in: .whitespaces)
                let secondNumber = values[1].trimmingCharacters(in: .whitespaces)
                let firstValue = convertToMmolL(firstNumber)
                let secondValue = convertToMmolL(secondNumber)
                let formattedString = "ISF: \(firstValue)→\(secondValue)"
                updatedTag.replaceSubrange(range, with: formattedString)

            } else if glucoseValueString.starts(with: "Dev:") {
                // -- Handle Dev
                let value = glucoseValueString.components(separatedBy: ":")[1].trimmingCharacters(in: .whitespaces)
                let formattedValue = convertToMmolL(value)
                let formattedString = "Dev: \(formattedValue)"
                updatedTag.replaceSubrange(range, with: formattedString)

            } else if glucoseValueString.starts(with: "BGI:") {
                // -- Handle BGI
                let value = glucoseValueString.components(separatedBy: ":")[1].trimmingCharacters(in: .whitespaces)
                let formattedValue = convertToMmolL(value)
                let formattedString = "BGI: \(formattedValue)"
                updatedTag.replaceSubrange(range, with: formattedString)

            } else if glucoseValueString.starts(with: "Target:") {
                // -- Handle Target
                let value = glucoseValueString.components(separatedBy: ":")[1].trimmingCharacters(in: .whitespaces)
                let formattedValue = convertToMmolL(value)
                let formattedString = "Target: \(formattedValue)"
                updatedTag.replaceSubrange(range, with: formattedString)

            } else {
                // -- Handle everything else (e.g., "minPredBG 39" etc.)
                let parts = glucoseValueString.components(separatedBy: .whitespaces)
                if parts.count >= 2 {
                    let metric = parts[0]
                    let value = parts[1]
                    let formattedValue = convertToMmolL(value)
                    let formattedString = "\(metric): \(formattedValue)"
                    updatedTag.replaceSubrange(range, with: formattedString)
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
            TagCloudView(
                tags: ["Apple", "Google", "Amazon", "Microsoft", "Oracle", "Facebook"],
                shouldParseToMmolL: false
            )
        }
    }
}
