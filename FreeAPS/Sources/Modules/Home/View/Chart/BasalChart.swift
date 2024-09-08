import Charts
import Foundation
import SwiftUI

struct BasalProfile: Hashable {
    let amount: Double
    var isOverwritten: Bool
    let startDate: Date
    let endDate: Date?
    init(amount: Double, isOverwritten: Bool, startDate: Date, endDate: Date? = nil) {
        self.amount = amount
        self.isOverwritten = isOverwritten
        self.startDate = startDate
        self.endDate = endDate
    }
}

extension MainChartView {
    var basalChart: some View {
        VStack {
            Chart {
                drawStartRuleMark()
                drawEndRuleMark()
                drawCurrentTimeMarker()
                drawTempBasals(dummy: false)
                drawBasalProfile()
                drawSuspensions()
            }.onChange(of: state.tempBasals) { _ in
                calculateBasals()
            }
            .onChange(of: state.maxBasal) { _ in
                calculateBasals()
            }
            .onChange(of: state.autotunedBasalProfile) { _ in
                calculateBasals()
            }
            .onChange(of: state.basalProfile) { _ in
                calculateBasals()
            }
            .frame(minHeight: geo.size.height * 0.05)
            .frame(width: fullWidth(viewWidth: screenSize.width))
            .chartXScale(domain: startMarker ... endMarker)
            .chartXAxis { basalChartXAxis }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartPlotStyle { basalChartPlotStyle($0) }
        }
    }
}

// MARK: - Draw functions

extension MainChartView {
    func drawTempBasals(dummy: Bool) -> some ChartContent {
        ForEach(prepareTempBasals(), id: \.rate) { basal in
            if dummy {
                RectangleMark(
                    xStart: .value("start", basal.start),
                    xEnd: .value("end", basal.end),
                    yStart: .value("rate-start", 0),
                    yEnd: .value("rate-end", basal.rate)
                ).foregroundStyle(Color.clear)

                LineMark(x: .value("Start Date", basal.start), y: .value("Amount", basal.rate))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.clear)

                LineMark(x: .value("End Date", basal.end), y: .value("Amount", basal.rate))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.clear)
            } else {
                RectangleMark(
                    xStart: .value("start", basal.start),
                    xEnd: .value("end", basal.end),
                    yStart: .value("rate-start", 0),
                    yEnd: .value("rate-end", basal.rate)
                ).foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(
                            colors: [
                                Color.insulin.opacity(0.6),
                                Color.insulin.opacity(0.1)
                            ]
                        ),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(x: .value("Start Date", basal.start), y: .value("Amount", basal.rate))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)

                LineMark(x: .value("End Date", basal.end), y: .value("Amount", basal.rate))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)
            }
        }
    }

    func drawBasalProfile() -> some ChartContent {
        /// dashed profile line
        ForEach(basalProfiles, id: \.self) { profile in
            LineMark(
                x: .value("Start Date", profile.startDate),
                y: .value("Amount", profile.amount),
                series: .value("profile", "profile")
            ).lineStyle(.init(lineWidth: 2, dash: [2, 4])).foregroundStyle(Color.insulin)
            LineMark(
                x: .value("End Date", profile.endDate ?? endMarker),
                y: .value("Amount", profile.amount),
                series: .value("profile", "profile")
            ).lineStyle(.init(lineWidth: 2.5, dash: [2, 4])).foregroundStyle(Color.insulin)
        }
    }

    func drawSuspensions() -> some ChartContent {
        let suspensions = state.suspensions
        return ForEach(suspensions) { suspension in
            let now = Date()

            if let type = suspension.type, type == EventType.pumpSuspend.rawValue, let suspensionStart = suspension.timestamp {
                let suspensionEnd = min(
                    (
                        suspensions
                            .first(where: {
                                $0.timestamp ?? now > suspensionStart && $0.type == EventType.pumpResume.rawValue })?
                            .timestamp
                    ) ?? now,
                    now
                )

                let basalProfileDuringSuspension = basalProfiles.first(where: { $0.startDate <= suspensionStart })
                let suspensionMarkHeight = basalProfileDuringSuspension?.amount ?? 1

                RectangleMark(
                    xStart: .value("start", suspensionStart),
                    xEnd: .value("end", suspensionEnd),
                    yStart: .value("suspend-start", 0),
                    yEnd: .value("suspend-end", suspensionMarkHeight)
                )
                .foregroundStyle(Color.loopGray.opacity(colorScheme == .dark ? 0.3 : 0.8))
            }
        }
    }
}

// MARK: - Calculation

extension MainChartView {
    func prepareTempBasals() -> [(start: Date, end: Date, rate: Double)] {
        let now = Date()
        let tempBasals = state.tempBasals

        return tempBasals.compactMap { temp -> (start: Date, end: Date, rate: Double)? in
            let duration = temp.tempBasal?.duration ?? 0
            let timestamp = temp.timestamp ?? Date()
            let end = min(timestamp + duration.minutes, now)
            let isInsulinSuspended = state.suspensions.contains { $0.timestamp ?? now >= timestamp && $0.timestamp ?? now <= end }

            let rate = Double(truncating: temp.tempBasal?.rate ?? Decimal.zero as NSDecimalNumber) * (isInsulinSuspended ? 0 : 1)

            // Check if there's a subsequent temp basal to determine the end time
            guard let nextTemp = state.tempBasals.first(where: { $0.timestamp ?? .distantPast > timestamp }) else {
                return (timestamp, end, rate)
            }
            return (timestamp, nextTemp.timestamp ?? Date(), rate) // end defaults to current time
        }
    }

    func findRegularBasalPoints(
        timeBegin: TimeInterval,
        timeEnd: TimeInterval,
        autotuned: Bool
    ) async -> [BasalProfile] {
        guard timeBegin < timeEnd else { return [] }

        let beginDate = Date(timeIntervalSince1970: timeBegin)
        let startOfDay = Calendar.current.startOfDay(for: beginDate)
        let profile = autotuned ? state.autotunedBasalProfile : state.basalProfile
        var basalPoints: [BasalProfile] = []

        // Iterate over the next three days, multiplying the time intervals
        for dayOffset in 0 ..< 3 {
            let dayTimeOffset = TimeInterval(dayOffset * 24 * 60 * 60) // One Day in seconds
            for entry in profile {
                let basalTime = startOfDay.addingTimeInterval(entry.minutes.minutes.timeInterval + dayTimeOffset)
                let basalTimeInterval = basalTime.timeIntervalSince1970

                // Only append points within the timeBegin and timeEnd range
                if basalTimeInterval >= timeBegin, basalTimeInterval < timeEnd {
                    basalPoints.append(BasalProfile(
                        amount: Double(entry.rate),
                        isOverwritten: false,
                        startDate: basalTime
                    ))
                }
            }
        }

        return basalPoints
    }

    func calculateBasals() {
        Task {
            let dayAgoTime = Date().addingTimeInterval(-1.days.timeInterval).timeIntervalSince1970

            // Get Regular and Autotuned Basal parallel
            async let getRegularBasalPoints = findRegularBasalPoints(
                timeBegin: dayAgoTime,
                timeEnd: endMarker.timeIntervalSince1970,
                autotuned: false
            )

            async let getAutotunedBasalPoints = findRegularBasalPoints(
                timeBegin: dayAgoTime,
                timeEnd: endMarker.timeIntervalSince1970,
                autotuned: true
            )

            let (regularPoints, autotunedBasalPoints) = await (getRegularBasalPoints, getAutotunedBasalPoints)

            var totalBasal = regularPoints + autotunedBasalPoints
            totalBasal.sort {
                $0.startDate.timeIntervalSince1970 < $1.startDate.timeIntervalSince1970
            }

            var basals: [BasalProfile] = []
            totalBasal.indices.forEach { index in
                basals.append(BasalProfile(
                    amount: totalBasal[index].amount,
                    isOverwritten: totalBasal[index].isOverwritten,
                    startDate: totalBasal[index].startDate,
                    endDate: totalBasal.count > index + 1 ? totalBasal[index + 1].startDate : endMarker
                ))
            }

            await MainActor.run {
                basalProfiles = basals
            }
        }
    }
}
