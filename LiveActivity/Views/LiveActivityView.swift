//
//  LiveActivityView.swift
//  Trio
//
//  Created by Cengiz Deniz on 17.10.24.
//
import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

struct LiveActivityView: View {
    @Environment(\.colorScheme) var colorScheme
    var context: ActivityViewContext<LiveActivityAttributes>

    private var hasStaticColorScheme: Bool {
        context.state.glucoseColorScheme == "staticColor"
    }

    private var glucoseColor: Color {
        let state = context.state
        let isMgdL = state.unit == "mg/dL"

        // TODO: workaround for now: set low value to 55, to have dynamic color shades between 55 and user-set low (approx. 70); same for high glucose
        let hardCodedLow = isMgdL ? Decimal(55) : 55.asMmolL
        let hardCodedHigh = isMgdL ? Decimal(220) : 220.asMmolL

        return Color.getDynamicGlucoseColor(
            glucoseValue: Decimal(string: state.bg) ?? 100,
            highGlucoseColorValue: !hasStaticColorScheme ? hardCodedHigh : state.highGlucose,
            lowGlucoseColorValue: !hasStaticColorScheme ? hardCodedLow : state.lowGlucose,
            targetGlucose: isMgdL ? state.target : state.target.asMmolL,
            glucoseColorScheme: state.glucoseColorScheme
        )
    }

    var body: some View {
        if let detailedViewState = context.state.detailedViewState {
            VStack {
                LiveActivityChartView(context: context, additionalState: detailedViewState)
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.9)
                    .frame(height: 80)
                    .overlay(alignment: .topTrailing) {
                        if detailedViewState.isOverrideActive {
                            HStack {
                                Text("\(detailedViewState.overrideName)")
                                    .font(.footnote)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                            }
                            .padding(6)
                            .background {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.purple.opacity(colorScheme == .dark ? 0.6 : 0.8))
                            }
                        }
                    }

                HStack {
                    if detailedViewState.widgetItems.contains(where: { $0 != .empty }) {
                        ForEach(Array(detailedViewState.widgetItems.enumerated()), id: \.element) { index, widgetItem in
                            switch widgetItem {
                            case .currentGlucose:
                                VStack {
                                    LiveActivityBGLabelView(context: context, additionalState: detailedViewState)

                                    HStack {
                                        LiveActivityGlucoseDeltaLabelView(
                                            context: context,
                                            glucoseColor: .primary
                                        )
                                        if !context.isStale, let direction = context.state.direction {
                                            Text(direction).font(.headline)
                                        }
                                    }
                                }
                            case .currentGlucoseLarge:
                                LiveActivityBGLabelLargeView(
                                    context: context,
                                    additionalState: detailedViewState,
                                    glucoseColor: glucoseColor
                                )
                            case .iob:
                                LiveActivityIOBLabelView(context: context, additionalState: detailedViewState)
                            case .cob:
                                LiveActivityCOBLabelView(context: context, additionalState: detailedViewState)
                            case .updatedLabel:
                                LiveActivityUpdatedLabelView(context: context, isDetailedLayout: true)
                            case .totalDailyDose:
                                LiveActivityTotalDailyDoseView(context: context, additionalState: detailedViewState)
                            case .empty:
                                Text("").frame(width: 50, height: 50)
                            }

                            /// Check if the next item is also non-empty to determine if a divider should be shown
                            if index < detailedViewState.widgetItems.count - 1 {
                                let currentItem = detailedViewState.widgetItems[index]
                                let nextItem = detailedViewState.widgetItems[index + 1]

                                if currentItem != .empty, nextItem != .empty {
                                    Divider()
                                        .foregroundStyle(.primary)
                                        .fontWeight(.bold)
                                        .frame(width: 10)
                                }
                            }
                        }
                    }
                }
            }
            .privacySensitive()
            .padding(.all, 14)
            .foregroundStyle(Color.primary)
            // Semantic BackgroundStyle and Color values work here. They adapt to the given interface style (light mode, dark mode)
            // Semantic UIColors do NOT (as of iOS 17.1.1). Like UIColor.systemBackgroundColor (it does not adapt to changes of the interface style)
            // The colorScheme environment variable does work here, but BackgroundStyle gives us this functionality for free
            .foregroundStyle(Color.primary)
            .background(BackgroundStyle.background.opacity(0.4))
            .activityBackgroundTint(Color.clear)
        } else {
            Group {
                if context.state.isInitialState {
                    Text("Live Activity Expired. Open Trio to Refresh").minimumScaleFactor(0.01)
                } else {
                    HStack(spacing: 3) {
                        LiveActivityBGAndTrendView(context: context, size: .expanded, glucoseColor: glucoseColor).font(.title)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            LiveActivityGlucoseDeltaLabelView(
                                context: context,
                                glucoseColor: hasStaticColorScheme ? .primary : glucoseColor
                            ).font(.title3)
                            LiveActivityUpdatedLabelView(context: context, isDetailedLayout: false).font(.caption)
                                .foregroundStyle(.primary.opacity(0.7))
                        }
                    }
                }
            }
            .privacySensitive()
            .padding(.all, 15)
            .foregroundStyle(Color.primary)
            /// Semantic BackgroundStyle and Color values work here. They adapt to the given interface style (light mode, dark mode)
            // Semantic UIColors do NOT (as of iOS 17.1.1). Like UIColor.systemBackgroundColor (it does not adapt to changes of the interface style)
            // The colorScheme environment variable does work here, but BackgroundStyle gives us this functionality for free
            .foregroundStyle(Color.primary)
            .background(BackgroundStyle.background.opacity(0.4))
            .activityBackgroundTint(Color.clear)
        }
    }
}

// Expanded, minimal, compact view components
struct LiveActivityExpandedLeadingView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    var glucoseColor: Color

    var body: some View {
        LiveActivityBGAndTrendView(context: context, size: .expanded, glucoseColor: glucoseColor).font(.title2)
            .padding(.leading, 5)
    }
}

struct LiveActivityExpandedTrailingView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    var glucoseColor: Color

    var body: some View {
        LiveActivityGlucoseDeltaLabelView(context: context, glucoseColor: glucoseColor).font(.title2)
            .padding(.trailing, 5)
    }
}

struct LiveActivityExpandedBottomView: View {
    var context: ActivityViewContext<LiveActivityAttributes>

    var body: some View {
        if context.state.isInitialState {
            Text("Live Activity Expired. Open Trio to Refresh").minimumScaleFactor(0.01)
        } else if let detailedViewState = context.state.detailedViewState {
            LiveActivityChartView(context: context, additionalState: detailedViewState)
        }
    }
}

struct LiveActivityExpandedCenterView: View {
    var context: ActivityViewContext<LiveActivityAttributes>

    var body: some View {
        LiveActivityUpdatedLabelView(context: context, isDetailedLayout: false).font(Font.caption)
            .foregroundStyle(Color.secondary)
    }
}

struct LiveActivityCompactLeadingView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    var glucoseColor: Color

    var body: some View {
        LiveActivityBGAndTrendView(context: context, size: .compact, glucoseColor: glucoseColor).padding(.leading, 4)
    }
}

struct LiveActivityCompactTrailingView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    var glucoseColor: Color

    var body: some View {
        LiveActivityGlucoseDeltaLabelView(context: context, glucoseColor: glucoseColor).padding(.trailing, 4)
    }
}

struct LiveActivityMinimalView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    var glucoseColor: Color

    var body: some View {
        let (label, characterCount) = bgAndTrend(context: context, size: .minimal, glucoseColor: glucoseColor)
        let adjustedLabel = label.padding(.leading, 5).padding(.trailing, 2)

        if characterCount < 4 {
            adjustedLabel.fontWidth(.condensed)
        } else if characterCount < 5 {
            adjustedLabel.fontWidth(.compressed)
        } else {
            adjustedLabel.fontWidth(.compressed)
        }
    }
}
