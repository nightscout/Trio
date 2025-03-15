import Charts
import Foundation
import SwiftUI

struct GlucoseChartView: ChartContent {
    let glucoseData: [GlucoseStored]
    let units: GlucoseUnits
    let highGlucose: Decimal
    let lowGlucose: Decimal
    let currentGlucoseTarget: Decimal
    let isSmoothingEnabled: Bool
    let glucoseColorScheme: GlucoseColorScheme

    var body: some ChartContent {
        drawGlucoseChart()
    }

    private func drawGlucoseChart() -> some ChartContent {
        ForEach(glucoseData) { item in
            let glucoseToDisplay = units == .mgdL ? Decimal(item.glucose) : Decimal(item.glucose).asMmolL

            // TODO: workaround for now: set low value to 55, to have dynamic color shades between 55 and user-set low (approx. 70); same for high glucose
            let hardCodedLow = Decimal(55)
            let hardCodedHigh = Decimal(220)
            let isDynamicColorScheme = glucoseColorScheme == .dynamicColor

            let pointMarkColor: Color = Trio.getDynamicGlucoseColor(
                glucoseValue: Decimal(item.glucose),
                highGlucoseColorValue: isDynamicColorScheme ? hardCodedHigh : highGlucose,
                lowGlucoseColorValue: isDynamicColorScheme ? hardCodedLow : lowGlucose,
                targetGlucose: currentGlucoseTarget,
                glucoseColorScheme: glucoseColorScheme
            )

            if !isSmoothingEnabled {
                PointMark(
                    x: .value("Time", item.date ?? Date(), unit: .second),
                    y: .value("Value", glucoseToDisplay)
                )
                .foregroundStyle(pointMarkColor)
                .symbolSize(20)
                .symbol {
                    if item.isManual {
                        Image(systemName: "drop.fill")
                            .font(.caption2)
                            .symbolRenderingMode(.monochrome)
                            .bold()
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .bold()
                            .foregroundStyle(pointMarkColor)
                    }
                }
            } else {
                PointMark(
                    x: .value("Time", item.date ?? Date(), unit: .second),
                    y: .value("Value", glucoseToDisplay)
                )
                .symbol {
                    if item.isManual {
                        Image(systemName: "drop.fill")
                            .font(.caption2)
                            .symbolRenderingMode(.monochrome)
                            .bold()
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: "record.circle.fill")
                            .font(.system(size: 8))
                            .bold()
                            .foregroundStyle(pointMarkColor)
                    }
                }
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var previewStack: CoreDataStack? = nil
        @State private var glucoseData: [GlucoseStored] = []
        @State private var isLoading = true

        var body: some View {
            NavigationView {
                Group {
                    if isLoading {
                        ProgressView("Loading data...")
                    } else {
                        VStack {
                            Chart {
                                GlucoseChartView(
                                    glucoseData: glucoseData,
                                    units: .mgdL,
                                    highGlucose: 180,
                                    lowGlucose: 70,
                                    currentGlucoseTarget: 100,
                                    isSmoothingEnabled: false,
                                    glucoseColorScheme: .dynamicColor
                                )
                            }
                            .frame(height: 200)
                            .padding()
                        }
                    }
                }
                .navigationTitle("Glucose Chart")
                .task {
                    // Use the preview stack that's initialized asynchronously in CoreDataStack
                    previewStack = try? await CoreDataStack.preview()

                    // Now you can safely create preview data
                    if let stack = previewStack {
                        glucoseData = GlucoseStored.makePreviewGlucose(count: 24, provider: stack)
                        isLoading = false
                    }
                }
            }
        }
    }

    return PreviewWrapper()
}
