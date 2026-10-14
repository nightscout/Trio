import Charts
import SwiftUI

struct DynamicISFExplorerChart: View {
    let curve: DynamicISFExplorer.Curve
    let savedCurve: DynamicISFExplorer.Curve?
    let units: GlucoseUnits

    @State private var selection: Double?

    private var selectedPoint: DynamicISFExplorer.Curve.Point? {
        guard let selection else { return nil }
        let glucose = Decimal(selection)
        return curve.point(nearest: units == .mgdL ? glucose : glucose / GlucoseUnits.exchangeRate)
    }

    private var sensitivityUnit: TherapySettingUnit {
        units == .mgdL ? .mgdLPerUnit : .mmolLPerUnit
    }

    private var maxSensitivity: Decimal {
        max(curve.sensitivityLimits.upperBound, savedCurve?.sensitivityLimits.upperBound ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading) {
            chart.frame(height: 240)
            legend
        }
    }

    private var chart: some View {
        Chart {
            RectangleMark(
                xStart: .value("Glucose", plotted(DynamicISFExplorer.Curve.glucoseRange.lowerBound)),
                xEnd: .value("Glucose", plotted(DynamicISFExplorer.Curve.glucoseRange.upperBound)),
                yStart: .value("ISF", plotted(curve.sensitivityLimits.lowerBound)),
                yEnd: .value("ISF", plotted(curve.sensitivityLimits.upperBound))
            )
            .foregroundStyle(Color.orange.opacity(0.15))

            RuleMark(y: .value("Profile ISF", plotted(curve.profileSensitivity)))
                .foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

            if let savedCurve {
                line(for: savedCurve, series: "saved")
                    .foregroundStyle(Color.cyan.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }

            line(for: curve, series: "explored")
                .foregroundStyle(Color.cyan)
                .lineStyle(StrokeStyle(lineWidth: 2))

            if let selectedPoint {
                RuleMark(x: .value("Glucose", plotted(selectedPoint.glucose)))
                    .foregroundStyle(Color.secondary)
                    .annotation(
                        position: .top,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        selectionPopover(for: selectedPoint)
                    }

                PointMark(
                    x: .value("Glucose", plotted(selectedPoint.glucose)),
                    y: .value("ISF", plotted(selectedPoint.sensitivity))
                )
                .foregroundStyle(Color.cyan)
            }
        }
        .chartXSelection(value: $selection)
        .chartXScale(
            domain: plotted(DynamicISFExplorer.Curve.glucoseRange.lowerBound) ...
                plotted(DynamicISFExplorer.Curve.glucoseRange.upperBound)
        )
        .chartYScale(domain: 0 ... plotted(maxSensitivity * 1.15))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(anchor: .top)
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel()
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
        }
        .chartXAxisLabel(units.rawValue, alignment: .trailing)
        .chartYAxisLabel(sensitivityUnit.displayName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Dynamic ISF chart by glucose"))
        .accessibilityValue(Text(accessibilitySummary))
    }

    private func line(for curve: DynamicISFExplorer.Curve, series: String) -> some ChartContent {
        ForEach(curve.points) { point in
            LineMark(
                x: .value("Glucose", plotted(point.glucose)),
                y: .value("ISF", plotted(point.sensitivity)),
                series: .value("Series", series)
            )
        }
    }

    private var legend: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                StatChartUtils.legendItem(label: String(localized: "Dynamic ISF"), color: Color.cyan)
                if savedCurve != nil {
                    StatChartUtils.legendItem(label: String(localized: "Your Settings"), color: Color.cyan.opacity(0.6))
                }
            }
            GridRow {
                StatChartUtils.legendItem(label: String(localized: "Profile ISF"), color: Color.secondary)
                StatChartUtils.legendItem(label: String(localized: "Autosens Limits"), color: Color.orange.opacity(0.3))
            }
        }
        // colour swatches mean nothing to VoiceOver; the chart's accessibility value describes the curve
        .accessibilityHidden(true)
    }

    private func selectionPopover(for point: DynamicISFExplorer.Curve.Point) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(formatted(point.glucose)) \(units.rawValue)").bold()
            Text("ISF \(formatted(point.sensitivity)) \(sensitivityUnit.displayName)")
            Text("Dynamic Ratio \(point.ratio.formatted(.percent.precision(.fractionLength(0))))")
        }
        .font(.footnote)
        .padding(7)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.chart.opacity(0.85))
                .shadow(color: Color.secondary, radius: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary, lineWidth: 2)
                )
        }
    }

    private var accessibilitySummary: String {
        guard let first = curve.points.first, let last = curve.points.last else { return "" }
        return String(
            localized: "ISF from \(formatted(first.sensitivity)) to \(formatted(last.sensitivity)) \(sensitivityUnit.spokenName)",
            comment: "Accessibility: chart summary"
        )
    }

    private func formatted(_ value: Decimal) -> String {
        NumberFormatter.glucoseFormatter(for: units).string(from: value.asUnit(units) as NSNumber) ?? "\(value)"
    }

    /// Glucose and ISF share a unit conversion, unrounded here so the curve stays smooth in mmol/L.
    private func plotted(_ value: Decimal) -> Double {
        Double(truncating: (units == .mgdL ? value : value * GlucoseUnits.exchangeRate) as NSNumber)
    }
}
