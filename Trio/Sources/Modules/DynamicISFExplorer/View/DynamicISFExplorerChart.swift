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

    private var sensitivityUnit: String {
        units == .mgdL ? String(localized: "mg/dL/U") : String(localized: "mmol/L/U")
    }

    private var maxSensitivity: Decimal {
        max(curve.sensitivityLimits.upperBound, savedCurve?.sensitivityLimits.upperBound ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading) {
            chart
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
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

            if let savedCurve {
                line(for: savedCurve, series: "saved")
                    .foregroundStyle(Color.cyan.opacity(0.4))
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
        .chartYAxisLabel(sensitivityUnit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Dynamic ISF chart by glucose"))
        .accessibilityValue(Text(accessibilitySummary))
    }

    private func line(for curve: DynamicISFExplorer.Curve, series: String) -> some ChartContent {
        ForEach(curve.points) { point in
            LineMark(
                x: .value("Glucose", plotted(point.glucose)),
                y: .value("ISF", plotted(point.sensitivity)),
                series: .value("Curve", series)
            )
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(String(localized: "Dynamic ISF"), color: Color.cyan)
            if savedCurve != nil {
                legendItem(String(localized: "Your Settings"), color: Color.cyan.opacity(0.4))
            }
            legendItem(String(localized: "Profile ISF"), color: Color.secondary)
            legendItem(String(localized: "Autosens Limits"), color: Color.orange.opacity(0.3))
        }
        .font(.caption2)
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.fill").foregroundStyle(color)
            Text(title).foregroundStyle(Color.secondary)
        }
    }

    private func selectionPopover(for point: DynamicISFExplorer.Curve.Point) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(formatted(point.glucose)) \(units.rawValue)").bold()
            Text("ISF \(formatted(point.sensitivity)) \(sensitivityUnit)")
            Text("Dynamic Ratio \(point.ratio.formatted(.percent.precision(.fractionLength(0))))")
        }
        .font(.caption)
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.chart.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary, lineWidth: 1)
                )
        }
    }

    private var accessibilitySummary: String {
        guard let first = curve.points.first, let last = curve.points.last else { return "" }
        return String(localized: "ISF from \(formatted(first.sensitivity)) to \(formatted(last.sensitivity)) \(sensitivityUnit)")
    }

    private func formatted(_ value: Decimal) -> String {
        NumberFormatter.glucoseFormatter(for: units).string(from: value.asUnit(units) as NSNumber) ?? "\(value)"
    }

    /// Glucose and ISF share a unit conversion, unrounded here so the curve stays smooth in mmol/L.
    private func plotted(_ value: Decimal) -> Double {
        Double(truncating: (units == .mgdL ? value : value * GlucoseUnits.exchangeRate) as NSNumber)
    }
}
