import SwiftUI

struct GRIChartView: View {
    let result: GRICalculator.Result
    let units: GlucoseUnits

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            summaryRow
            riskGrid
            Divider()
            explanation
        }
    }

    private var summaryRow: some View {
        HStack {
            Text("GRI")
                .font(.subheadline.weight(.semibold))
            Text(StatChartUtils.format(result.score))
                .font(.headline)
            Text("/ 100")
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(GRIColors.zoneColor(forZone: result.zone))
                    .frame(width: 10, height: 10)
                Text("Zone \(result.zone)")
            }
        }
    }

    private var riskGrid: some View {
        Canvas { context, size in
            let xMax = max(30, ceil(result.hypoComponent / 5) * 5)
            let yMax = max(60, ceil(result.hyperComponent / 10) * 10)
            let side = max(1, size.width - 60)
            let plot = CGRect(x: 48, y: 8, width: side, height: side)
            let background = Color(uiColor: .systemBackground)
            let labelFont = Font.system(size: 11)

            var plotContext = context
            plotContext.clip(to: Path(plot))
            plotContext.fill(Path(plot), with: .color(background))
            for zone in GRIColors.zones.reversed() {
                var band = Path()
                band.move(to: CGPoint(x: plot.minX, y: plot.maxY))
                band.addLine(to: CGPoint(x: plot.minX + zone.maxScore / 3 / xMax * side, y: plot.maxY))
                band.addLine(to: CGPoint(x: plot.minX, y: plot.maxY - zone.maxScore / 1.6 / yMax * side))
                band.closeSubpath()
                plotContext.fill(band, with: .color(background))
                plotContext.fill(band, with: .color(zone.color.opacity(colorScheme == .dark ? 0.75 : 1)))
            }
            context.stroke(Path(plot), with: .foreground, lineWidth: 1)

            for step in 0 ... 6 {
                let fraction = Double(step) / 6
                context.draw(
                    Text((fraction * xMax).formatted(.number.precision(.fractionLength(0 ... 1))))
                        .font(labelFont).foregroundStyle(.primary),
                    at: CGPoint(x: plot.minX + fraction * side, y: plot.maxY + 12)
                )
                context.draw(
                    Text((fraction * yMax).formatted(.number.precision(.fractionLength(0 ... 1))))
                        .font(labelFont).foregroundStyle(.primary),
                    at: CGPoint(x: plot.minX - 7, y: plot.maxY - fraction * side),
                    anchor: .trailing
                )
            }
            context.draw(
                Text("Hypoglycemia Component (%)").font(.caption).foregroundStyle(.primary),
                at: CGPoint(x: plot.midX, y: plot.maxY + 35)
            )
            var verticalContext = context
            verticalContext.translateBy(x: 10, y: plot.midY)
            verticalContext.rotate(by: .degrees(-90))
            verticalContext.draw(
                Text("Hyperglycemia Component (%)").font(.caption).foregroundStyle(.primary),
                at: .zero
            )

            let legendFont = Font.system(size: min(12, side * 0.042))
            let rowHeight: CGFloat = 18
            let legendWidth = min(146, side * 0.55)
            let legend = CGRect(
                x: plot.maxX - legendWidth - 10,
                y: plot.minY + 16,
                width: legendWidth,
                height: rowHeight * 5 + 12
            )
            context.fill(Path(legend), with: .color(background))
            context.stroke(Path(legend), with: .foreground, lineWidth: 1)
            for (index, zone) in GRIColors.zones.enumerated() {
                let y = legend.minY + 6 + CGFloat(index) * rowHeight + rowHeight / 2
                let swatch = CGRect(x: legend.minX + 6, y: y - 5, width: 10, height: 10)
                context.fill(Path(swatch), with: .color(zone.color.opacity(colorScheme == .dark ? 0.75 : 1)))
                context.stroke(Path(swatch), with: .foreground, lineWidth: 0.5)
                context.draw(
                    Text(zone.title).font(legendFont).foregroundStyle(.primary),
                    at: CGPoint(x: swatch.maxX + 5, y: y), anchor: .leading
                )
            }

            let point = CGPoint(
                x: plot.minX + result.hypoComponent / xMax * side,
                y: plot.maxY - result.hyperComponent / yMax * side
            )
            let marker = Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
            context.fill(marker, with: .foreground)
            context.stroke(marker, with: .color(background), lineWidth: 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("GRI risk grid, zone \(result.zone)")
        .accessibilityValue(
            "Hypoglycemia \(StatChartUtils.formatPercentage(result.hypoComponent)), hyperglycemia \(StatChartUtils.formatPercentage(result.hyperComponent))"
        )
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                "Glycemia Risk Index combines low and high glucose exposure into a score from 0 to 100. Lower scores indicate less glycemic risk."
            )
            Text(
                "Calculated from glucose readings in the selected period. Short periods and gaps in sensor data can make the score less representative."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            bandRow(String(localized: "Hypoglycemia component"), value: result.hypoComponent, color: GRIColors.hypo)
            bandRow(String(localized: "Hyperglycemia component"), value: result.hyperComponent, color: GRIColors.hyper)
            Divider()
            DisclosureGroup("Score calculation") {
                scoreBreakdown
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scoreBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GRI uses fixed glucose thresholds, regardless of your target range.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            bandRow(.veryLow, value: result.veryLowPercentage, color: GRIColors.veryLow)
            bandRow(.low, value: result.lowPercentage, color: GRIColors.low)
            bandRow(.high, value: result.highPercentage, color: GRIColors.high)
            bandRow(.veryHigh, value: result.veryHighPercentage, color: GRIColors.veryHigh)
            Divider()
            calculation(
                "Hypoglycemia component",
                color: GRIColors.hypo,
                formula: patientValue(StatChartUtils.format(result.veryLowPercentage), color: GRIColors.veryLow) +
                    AttributedString(" + \(StatChartUtils.format(0.8)) × ") +
                    patientValue(StatChartUtils.format(result.lowPercentage), color: GRIColors.low) +
                    AttributedString(" = ") +
                    patientValue(StatChartUtils.format(result.hypoComponent), color: GRIColors.hypo)
            )
            calculation(
                "Hyperglycemia component",
                color: GRIColors.hyper,
                formula: patientValue(StatChartUtils.format(result.veryHighPercentage), color: GRIColors.veryHigh) +
                    AttributedString(" + \(StatChartUtils.format(0.5)) × ") +
                    patientValue(StatChartUtils.format(result.highPercentage), color: GRIColors.high) +
                    AttributedString(" = ") +
                    patientValue(StatChartUtils.format(result.hyperComponent), color: GRIColors.hyper)
            )
            calculation(
                "Combined score",
                formula: AttributedString("3 × ") +
                    patientValue(StatChartUtils.format(result.hypoComponent), color: GRIColors.hypo) +
                    AttributedString(" + \(StatChartUtils.format(1.6)) × ") +
                    patientValue(StatChartUtils.format(result.hyperComponent), color: GRIColors.hyper) +
                    AttributedString(" = ") +
                    patientValue(StatChartUtils.format(result.uncappedScore), color: .primary)
            )
            Divider()
            Text("The final GRI score is capped at 100. Calculations use unrounded values.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            LabeledContent("GRI") {
                Text(StatChartUtils.format(result.score))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .font(.headline)
        }
    }

    private func bandRow(_ band: GlucoseBand, value: Double, color: Color) -> some View {
        bandRow("\(band.rangeLabel(units: units)) \(units.rawValue)", value: value, color: color)
    }

    private func bandRow(_ label: String, value: Double, color: Color) -> some View {
        LabeledContent(label) {
            Text(StatChartUtils.formatPercentage(value))
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
        }
    }

    private func calculation(_ title: LocalizedStringKey, color: Color = .primary, formula: AttributedString) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            Text(formula).monospacedDigit()
        }
    }

    private func patientValue(_ value: String, color: Color) -> AttributedString {
        var text = AttributedString(value)
        text.foregroundColor = color
        text.font = .body.weight(.semibold)
        return text
    }

    private enum GRIColors {
        static let zones: [(maxScore: Double, title: LocalizedStringKey, color: Color)] = [
            (20, "Zone A (0-20)", Color(red: 0.48, green: 0.74, blue: 0.46)),
            (40, "Zone B (>20-40)", Color(red: 0.98, green: 0.96, blue: 0.48)),
            (60, "Zone C (>40-60)", Color(red: 1.00, green: 0.82, blue: 0.49)),
            (80, "Zone D (>60-80)", Color(red: 0.95, green: 0.46, blue: 0.48)),
            (100, "Zone E (>80-100)", Color(red: 0.79, green: 0.57, blue: 0.55))
        ]

        static func zoneColor(forZone zone: String) -> Color {
            let index = ["A", "B", "C", "D", "E"].firstIndex(of: zone) ?? 4
            return zones[index].color
        }

        static let veryLow: Color = .dynamicRed
        static let low = veryLow.opacity(0.65)
        static let high = veryHigh.opacity(0.65)
        static let veryHigh: Color = .dynamicPurple
        // Component accents share the extreme band hues.
        static let hypo = veryLow
        static let hyper = veryHigh
    }
}
