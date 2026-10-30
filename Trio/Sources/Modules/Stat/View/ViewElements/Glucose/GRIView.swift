import SwiftUI

struct GRIChartView: View {
    let result: GRICalculator.Result?
    let units: GlucoseUnits

    var body: some View {
        VStack(spacing: 16) {
            GRIView(result: result, units: units)
            if let result {
                GRIRiskGridView(result: result)
            } else {
                ContentUnavailableView("No Glucose Data", systemImage: "chart.bar.fill")
            }
        }
    }
}

struct GRIView: View {
    let result: GRICalculator.Result?
    let units: GlucoseUnits
    @State private var showingDetails = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            showingDetails = true
        } label: {
            HStack {
                Text("GRI")
                    .font(.subheadline.weight(.semibold))
                if let result {
                    Text(result.score, format: .number.precision(.fractionLength(1)))
                        .font(.headline)
                    Text("/ 100")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Zone \(result.zone)")
                        .foregroundStyle(griColor(result.score))
                } else {
                    Text("—")
                    Spacer()
                }
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows Glycemia Risk Index details")
        .sheet(isPresented: $showingDetails) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let result {
                            HStack {
                                Text(result.score, format: .number.precision(.fractionLength(1)))
                                    .font(.largeTitle.bold())
                                Text("/ 100")
                                Spacer()
                                Text("Zone \(result.zone)")
                                    .foregroundStyle(griColor(result.score))
                            }
                            GRIRiskGridView(result: result)
                        } else {
                            ContentUnavailableView("No Glucose Data", systemImage: "chart.bar.fill")
                        }
                        GRIExplanationView(result: result, units: units)
                    }
                    .padding()
                }
                .background(Color(uiColor: .systemBackground))
                .navigationTitle("Glycemia Risk Index")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingDetails = false }
                    }
                }
            }
            .preferredColorScheme(colorScheme)
            .presentationBackground(Color(uiColor: .systemBackground))
        }
    }
}

struct GRIExplanationView: View {
    let result: GRICalculator.Result?
    let units: GlucoseUnits

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                "Glycemia Risk Index combines low and high glucose exposure into a score from 0 to 100. Lower scores indicate less glycemic risk."
            )
            Text(
                "Calculated from glucose readings in the selected period. Short periods and gaps in sensor data can make the score less representative."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            if let result {
                LabeledContent("Hypoglycemia component", value: component(result.hypoComponent))
                    .foregroundStyle(GRICalculationColors.hypo)
                LabeledContent("Hyperglycemia component", value: component(result.hyperComponent))
                    .foregroundStyle(GRICalculationColors.hyper)
            }
            Divider()
            if let result {
                DisclosureGroup("Score calculation") {
                    GRIScoreBreakdownView(result: result, units: units)
                        .padding(.top, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func component(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "%"
    }
}

private enum GRICalculationColors {
    static let veryLow: Color = .dynamicRed
    static let low = veryLow.opacity(0.65)
    static let high = veryHigh.opacity(0.65)
    static let veryHigh: Color = .dynamicPurple
    static let hypo = veryLow
    static let hyper = veryHigh
}

private struct GRIScoreBreakdownView: View {
    let result: GRICalculator.Result
    let units: GlucoseUnits

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GRI uses fixed glucose thresholds, regardless of your target range or display units.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            LabeledContent("Below \(54.formatted(withUnits: units))") {
                Text(patientValue(percentage(result.veryLowPercentage), color: GRICalculationColors.veryLow))
            }
            LabeledContent("\(54.formatted(for: units)) to below \(70.formatted(withUnits: units))") {
                Text(patientValue(percentage(result.lowPercentage), color: GRICalculationColors.low))
            }
            LabeledContent("Above \(180.formatted(for: units)) through \(250.formatted(withUnits: units))") {
                Text(patientValue(percentage(result.highPercentage), color: GRICalculationColors.high))
            }
            LabeledContent("Above \(250.formatted(withUnits: units))") {
                Text(patientValue(percentage(result.veryHighPercentage), color: GRICalculationColors.veryHigh))
            }

            Divider()
            calculation(
                "Hypoglycemia component",
                color: GRICalculationColors.hypo,
                formula: patientValue(number(result.veryLowPercentage), color: GRICalculationColors.veryLow) +
                    AttributedString(" + \(number(0.8)) × ") +
                    patientValue(number(result.lowPercentage), color: GRICalculationColors.low) + AttributedString(" = ") +
                    patientValue(number(result.hypoComponent), color: GRICalculationColors.hypo)
            )
            calculation(
                "Hyperglycemia component",
                color: GRICalculationColors.hyper,
                formula: patientValue(number(result.veryHighPercentage), color: GRICalculationColors.veryHigh) +
                    AttributedString(" + \(number(0.5)) × ") +
                    patientValue(number(result.highPercentage), color: GRICalculationColors.high) + AttributedString(" = ") +
                    patientValue(number(result.hyperComponent), color: GRICalculationColors.hyper)
            )
            calculation(
                "Weighted hypoglycemia",
                color: GRICalculationColors.hypo,
                formula: AttributedString("3 × ") + patientValue(number(result.hypoComponent), color: GRICalculationColors.hypo) +
                    AttributedString(" = ") +
                    patientValue(number(result.weightedHypoComponent), color: GRICalculationColors.hypo)
            )
            calculation(
                "Weighted hyperglycemia",
                color: GRICalculationColors.hyper,
                formula: AttributedString("\(number(1.6)) × ") +
                    patientValue(number(result.hyperComponent), color: GRICalculationColors.hyper) +
                    AttributedString(" = ") +
                    patientValue(number(result.weightedHyperComponent), color: GRICalculationColors.hyper)
            )
            calculation(
                "Combined score",
                formula: patientValue(number(result.weightedHypoComponent), color: GRICalculationColors.hypo) +
                    AttributedString(" + ") +
                    patientValue(number(result.weightedHyperComponent), color: GRICalculationColors.hyper) +
                    AttributedString(" = ") +
                    patientValue(number(result.uncappedScore), color: .primary)
            )
            Text("The final GRI score is capped at 100. Calculations use unrounded values.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            LabeledContent("GRI") {
                Text(patientValue(number(result.score), color: .primary))
            }
            .font(.headline)
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

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func percentage(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(1)))
    }
}

private func griColor(_ score: Double) -> Color {
    switch score {
    case ...20: return .green
    case ...40: return .yellow
    case ...60: return .orange
    case ...80: return .red
    default: return Color(red: 0.58, green: 0.30, blue: 0.28)
    }
}

private struct GRIRiskGridView: View {
    let result: GRICalculator.Result
    @Environment(\.colorScheme) private var colorScheme

    private var xMax: Double { max(30, ceil(result.hypoComponent / 5) * 5) }
    private var yMax: Double { max(60, ceil(result.hyperComponent / 10) * 10) }

    private let zones: [(score: Double, title: LocalizedStringKey, color: Color)] = [
        (20, "Zone A (0-20)", Color(red: 0.48, green: 0.74, blue: 0.46)),
        (40, "Zone B (>20-40)", Color(red: 0.98, green: 0.96, blue: 0.48)),
        (60, "Zone C (>40-60)", Color(red: 1.00, green: 0.82, blue: 0.49)),
        (80, "Zone D (>60-80)", Color(red: 0.95, green: 0.46, blue: 0.48)),
        (100, "Zone E (>80-100)", Color(red: 0.79, green: 0.57, blue: 0.55))
    ]

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let side = max(1, size.width - 60)
                let plot = CGRect(x: 48, y: 8, width: side, height: side)
                let background = Color(uiColor: .systemBackground)
                let labelFont = Font.system(size: 11)

                var plotContext = context
                plotContext.clip(to: Path(plot))
                plotContext.fill(Path(plot), with: .color(background))
                for zone in zones.reversed() {
                    var band = Path()
                    band.move(to: CGPoint(x: plot.minX, y: plot.maxY))
                    band.addLine(to: CGPoint(x: plot.minX + zone.score / 3 / xMax * side, y: plot.maxY))
                    band.addLine(to: CGPoint(x: plot.minX, y: plot.maxY - zone.score / 1.6 / yMax * side))
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
                for (index, zone) in zones.enumerated() {
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
            .frame(height: geometry.size.width - 8)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("GRI risk grid, zone \(result.zone)")
        .accessibilityValue(
            "Hypoglycemia \(result.hypoComponent.formatted()) percent, hyperglycemia \(result.hyperComponent.formatted()) percent"
        )
    }
}
