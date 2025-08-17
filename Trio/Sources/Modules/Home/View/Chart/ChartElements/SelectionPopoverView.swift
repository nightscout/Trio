import Charts
import Foundation
import SwiftUI

struct SelectionPopoverView: ChartContent {
    let selectedGlucose: GlucoseStored
    let selectedIOBValue: OrefDetermination?
    let selectedCOBValue: OrefDetermination?
    let units: GlucoseUnits
    let highGlucose: Decimal
    let lowGlucose: Decimal
    let currentGlucoseTarget: Decimal
    let glucoseColorScheme: GlucoseColorScheme

    private var glucoseToDisplay: Decimal {
        units == .mgdL ? Decimal(selectedGlucose.glucose) : Decimal(selectedGlucose.glucose).asMmolL
    }

    private var pointMarkColor: Color {
        let hardCodedLow = Decimal(55)
        let hardCodedHigh = Decimal(220)
        let isDynamicColorScheme = glucoseColorScheme == .dynamicColor

        return Trio.getDynamicGlucoseColor(
            glucoseValue: Decimal(selectedGlucose.glucose),
            highGlucoseColorValue: isDynamicColorScheme ? hardCodedHigh : highGlucose,
            lowGlucoseColorValue: isDynamicColorScheme ? hardCodedLow : lowGlucose,
            targetGlucose: currentGlucoseTarget,
            glucoseColorScheme: glucoseColorScheme
        )
    }

    var body: some ChartContent {
        RuleMark(x: .value("Selection", selectedGlucose.date ?? Date.now, unit: .minute))
            .foregroundStyle(Color.tabBar)
            .offset(yStart: 70)
            .lineStyle(.init(lineWidth: 2))
            .annotation(
                position: .top,
                alignment: .center,
                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
            ) {
                selectionPopover
            }

        PointMark(
            x: .value("Time", selectedGlucose.date ?? Date.now, unit: .minute),
            y: .value("Value", glucoseToDisplay)
        )
        .zIndex(-1)
        .symbolSize(CGSize(width: 15, height: 15))
        .foregroundStyle(pointMarkColor)

        PointMark(
            x: .value("Time", selectedGlucose.date ?? Date.now, unit: .minute),
            y: .value("Value", glucoseToDisplay)
        )
        .zIndex(-1)
        .symbolSize(CGSize(width: 6, height: 6))
        .foregroundStyle(Color.primary)
    }

    @ViewBuilder var selectionPopover: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(selectedGlucose.date?.formatted(.dateTime.hour().minute(.twoDigits)) ?? "")
                    .font(.caption).bold()
            }
            .padding(.bottom, 1)

            HStack {
                Text(glucoseToDisplay.description).bold() + Text(" \(units.rawValue)")
            }
            .foregroundStyle(pointMarkColor)
            .font(.caption)

            if let selectedIOBValue, let iob = selectedIOBValue.iob {
                HStack(spacing: 4) {
                    Image(systemName: "syringe.fill").frame(width: 12)
                        .font(.caption2)
                        .foregroundColor(.insulin)
                    Text(Formatter.bolusFormatter.string(from: iob) ?? "")
                        .bold()
                        + Text(String(localized: " U", comment: "Insulin unit"))
                }
                .foregroundStyle(Color.insulin)
                .font(.caption2)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            if let selectedCOBValue {
                HStack(spacing: 4) {
                    Image(systemName: "fork.knife").frame(width: 12)
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text(Formatter.integerFormatter.string(from: selectedCOBValue.cob as NSNumber) ?? "")
                        .bold()
                        + Text(String(localized: " g", comment: "gram of carbs"))
                }
                .foregroundStyle(Color.orange)
                .font(.caption2)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.chart.opacity(0.9))
                .shadow(color: Color.secondary.opacity(0.3), radius: 1.5, x: 0, y: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                )
        }
        .animation(.easeInOut(duration: 0.15), value: selectedGlucose.date)
        .animation(.easeInOut(duration: 0.15), value: selectedIOBValue?.iob)
        .animation(.easeInOut(duration: 0.15), value: selectedCOBValue?.cob)
        .drawingGroup() // Optimize for frequent updates
    }
}
