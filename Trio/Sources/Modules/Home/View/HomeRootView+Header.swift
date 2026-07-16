import SwiftUI
import UIKit

// MARK: - Zone B: header (pump panel / glucose bobble / loop status)

extension Home.RootView {
    var cgmSelectionButtons: some View {
        ForEach(cgmOptions, id: \.name) { option in
            if let cgm = state.listOfCGM.first(where: option.predicate) {
                Button(option.name) {
                    state.addCGM(cgm: cgm)
                }
            }
        }
    }

    var glucoseView: some View {
        CurrentGlucoseView(
            timerDate: state.timerDate,
            units: state.units,
            alarm: state.alarm,
            lowGlucose: state.lowGlucose,
            highGlucose: state.highGlucose,
            cgmAvailable: state.cgmAvailable,
            currentGlucoseTarget: state.currentGlucoseTarget,
            glucoseColorScheme: state.glucoseColorScheme,
            glucose: state.latestTwoGlucoseValues,
            cgmProgress: state.cgmProgressHighlight,
            cgmStatus: state.cgmDisplayState,
            cgmSensorExpiresAt: state.cgmSensorExpiresAt,
            cgmWarmupEndsAt: state.cgmWarmupEndsAt
        )
        .onTapGesture {
            if !state.cgmAvailable {
                showCGMSelection.toggle()
            } else {
                state.shouldDisplayCGMSetupSheet.toggle()
            }
        }
        .onLongPressGesture {
            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
            impactHeavy.impactOccurred()
            showSnoozeSheet = true
        }
    }

    var pumpView: some View {
        PumpView(
            reservoir: state.reservoir,
            name: state.pumpName,
            expiresAtDate: state.pumpExpiresAtDate,
            activatedAtDate: state.pumpActivatedAtDate,
            timerDate: state.timerDate,
            pumpStatusHighlightMessage: state.pumpStatusHighlightMessage,
            battery: state.batteryFromPersistence
        )
        .onTapGesture {
            if state.pumpDisplayState == nil {
                // shows user confirmation dialog with pump model choices, then proceeds to setup
                showPumpSelection.toggle()
            } else {
                // sends user to pump settings
                state.shouldDisplayPumpSetupSheet.toggle()
            }
        }
    }

    @ViewBuilder func rightHeaderPanel() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            /// Loop view at bottomLeading
            LoopView(
                closedLoop: state.closedLoop,
                timerDate: state.timerDate,
                isLooping: state.isLooping,
                lastLoopDate: state.lastLoopDate,
                manualTempBasal: state.manualTempBasal,
                determination: state.determinationsFromPersistence
            )
            .onTapGesture {
                state.isLoopStatusPresented = true
            }
            /// eventualBG string at bottomTrailing

            if let eventualBG = state.enactedAndNonEnactedDeterminations.first?.eventualBG {
                let eventualGlucose = eventualBG as Decimal
                HStack {
                    Image(systemName: "arrow.right.circle")
                        .font(.callout)
                        .fontWeight(.bold)

                    Text(state.units == .mgdL ? eventualGlucose.description : eventualGlucose.formattedAsMmolL)
                        .font(.callout)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                }
                // aligns the evBG icon exactly with the first pixel of loop status icon
                .padding(.leading, 12)
            } else {
                HStack {
                    Image(systemName: "arrow.right.circle")
                        .font(.callout).fontWeight(.bold)
                    Text("--")
                        .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                }
            }
        }
    }
}
