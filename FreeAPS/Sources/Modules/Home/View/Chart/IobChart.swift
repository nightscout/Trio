import Charts
import Foundation
import SwiftUI

extension MainChartView {
    var iobChart: some View {
        VStack {
            Chart {
                drawIOB()

                if #available(iOS 17, *) {
                    if let selectedIOBValue {
                        PointMark(
                            x: .value("Time", selectedIOBValue.deliverAt ?? now, unit: .minute),
                            y: .value("Value", Int(truncating: selectedIOBValue.iob ?? 0))
                        )
                        .symbolSize(CGSize(width: 15, height: 15))
                        .foregroundStyle(Color.darkerBlue.opacity(0.8))

                        PointMark(
                            x: .value("Time", selectedIOBValue.deliverAt ?? now, unit: .minute),
                            y: .value("Value", Int(truncating: selectedIOBValue.iob ?? 0))
                        )
                        .symbolSize(CGSize(width: 6, height: 6))
                        .foregroundStyle(Color.primary)
                    }
                }
            }
            .offset(y: deviceOffset)
            .frame(minHeight: geo.size.height * 0.12)
            .frame(width: fullWidth(viewWidth: screenSize.width))
            .chartXScale(domain: startMarker ... endMarker)
            .backport.chartXSelection(value: $selection)
            .chartXAxis { basalChartXAxis }
            .chartXAxis(.hidden)
            .chartYAxis { cobChartYAxis }
            .chartYScale(domain: state.minValueIobChart ... state.maxValueIobChart)
            .chartYAxis(.hidden)
        }
    }

    var deviceOffset: CGFloat {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            // Use the native screen height in pixels to calculate the offset for different devices
            // The offset is based on the empirically determined offset for the iPhone 16 Pro simulator (2622 pixels in height, offset = 11)
            // The offset for other devices is calculated proportionally to the iPhone 16 Pro:
            // Offset for another device = (Height of the other device / Height of iPhone 16 Pro) * 11
            let screenHeight = UIScreen.main.nativeBounds.height
            if screenHeight == 2622 {
                return 11 // iPhone 16 Pro
            } else if screenHeight == 2868 {
                return 12.1 // iPhone 16 Pro Max
            } else if screenHeight == 2556 {
                return 10.7 // iPhone 15 Pro
            } else if screenHeight == 2796 {
                return 11.7 // iPhone 15 Pro Max / 15 Plus / 16 Plus
            } else if screenHeight == 2340 {
                return 9.8 // iPhone 12 Mini
            } else {
                return 11 // Default for other phones
            }
        default:
            return 11
        }
    }

    func drawIOB() -> some ChartContent {
        ForEach(state.enactedAndNonEnactedDeterminations) { iob in
            let rawAmount = iob.iob?.doubleValue ?? 0
            let amount: Double = rawAmount > 0 ? rawAmount : rawAmount * 2 // weigh negative iob with factor 2
            let date: Date = iob.deliverAt ?? Date()

            LineMark(x: .value("Time", date), y: .value("Amount", amount))
                .foregroundStyle(Color.darkerBlue)
            AreaMark(x: .value("Time", date), y: .value("Amount", amount))
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(
                            colors: [
                                Color.darkerBlue.opacity(0.8),
                                Color.darkerBlue.opacity(0.01)
                            ]
                        ),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}
