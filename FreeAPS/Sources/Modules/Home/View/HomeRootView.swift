import CoreData
import SpriteKit
import SwiftDate
import SwiftUI
import Swinject

struct TimePicker: Identifiable {
    let label: String
    let number: String
    var active: Bool
    let hours: Int16
    var id: String { label }
}

extension Home {
    struct RootView: BaseView {
        let resolver: Resolver
        let safeAreaSize: CGFloat = 0.08

        @Environment(\.managedObjectContext) var moc
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        @State var state = StateModel()

        @State var settingsPath = NavigationPath()
        @State var isStatusPopupPresented = false
        @State var showCancelAlert = false
        @State var showCancelConfirmDialog = false
        @State var isConfirmStopOverrideShown = false
        @State var isConfirmStopOverridePresented = false
        @State var isConfirmStopTempTargetShown = false
        @State var isMenuPresented = false
        @State var showTreatments = false
        @State var selectedTab: Int = 0
        @State private var statusTitle: String = ""
        @State var showPumpSelection: Bool = false
        @State var notificationsDisabled = false
        @State var timeButtons: [TimePicker] = [
            TimePicker(label: "2 hours", number: "2", active: false, hours: 2),
            TimePicker(label: "4 hours", number: "4", active: false, hours: 4),
            TimePicker(label: "6 hours", number: "6", active: false, hours: 6),
            TimePicker(label: "12 hours", number: "12", active: false, hours: 12),
            TimePicker(label: "24 hours", number: "24", active: false, hours: 24)
        ]

        let buttonFont = Font.custom("TimeButtonFont", size: 14)

        @FetchRequest(fetchRequest: OverrideStored.fetch(
            NSPredicate.lastActiveOverride,
            ascending: false,
            fetchLimit: 1
        )) var latestOverride: FetchedResults<OverrideStored>

        @FetchRequest(fetchRequest: TempTargetStored.fetch(
            NSPredicate.lastActiveTempTarget,
            ascending: false,
            fetchLimit: 1
        )) var latestTempTarget: FetchedResults<TempTargetStored>

        var bolusProgressFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimum = 0
            formatter.maximumFractionDigits = state.settingsManager.preferences.bolusIncrement > 0.05 ? 1 : 2
            formatter.minimumFractionDigits = state.settingsManager.preferences.bolusIncrement > 0.05 ? 1 : 2
            formatter.allowsFloats = true
            formatter.roundingIncrement = Double(state.settingsManager.preferences.bolusIncrement) as NSNumber
            return formatter
        }

        private var fetchedTargetFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
            } else { formatter.maximumFractionDigits = 0 }
            return formatter
        }

        private var historySFSymbol: String {
            if #available(iOS 17.0, *) {
                return "book.pages"
            } else {
                return "book"
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
                glucose: state.latestTwoGlucoseValues
            ).scaleEffect(0.9)
                .onTapGesture {
                    state.openCGM()
                }
                .onLongPressGesture {
                    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                    impactHeavy.impactOccurred()
                    state.showModal(for: .snooze)
                }
        }

        var pumpView: some View {
            PumpView(
                reservoir: state.reservoir,
                name: state.pumpName,
                expiresAtDate: state.pumpExpiresAtDate,
                timerDate: state.timerDate,
                timeZone: state.timeZone,
                pumpStatusHighlightMessage: state.pumpStatusHighlightMessage,
                battery: state.batteryFromPersistence
            ).onTapGesture {
                if state.pumpDisplayState == nil {
                    // shows user confirmation dialog with pump model choices, then proceeds to setup
                    showPumpSelection.toggle()
                } else {
                    // sends user to pump settings
                    state.setupPump.toggle()
                }
            }
        }

        var tempBasalString: String? {
            guard let lastTempBasal = state.tempBasals.last?.tempBasal, let tempRate = lastTempBasal.rate else {
                return nil
            }
            let rateString = Formatter.decimalFormatterWithTwoFractionDigits.string(from: tempRate as NSNumber) ?? "0"
            var manualBasalString = ""

            if let apsManager = state.apsManager, apsManager.isManualTempBasal {
                manualBasalString = NSLocalizedString(
                    " - Manual Basal ⚠️",
                    comment: "Manual Temp basal"
                )
            }

            return rateString + " " + NSLocalizedString(" U/hr", comment: "Unit per hour with space") + manualBasalString
        }

        var overrideString: String? {
            guard let latestOverride = latestOverride.first else {
                return nil
            }

            let percent = latestOverride.percentage
            let percentString = percent == 100 ? "" : "\(percent.formatted(.number)) %"

            let unit = state.units
            var target = (latestOverride.target ?? 100) as Decimal
            target = unit == .mmolL ? target.asMmolL : target

            var targetString = target == 0 ? "" : (fetchedTargetFormatter.string(from: target as NSNumber) ?? "") + " " + unit
                .rawValue
            if tempTargetString != nil {
                targetString = ""
            }

            let duration = latestOverride.duration ?? 0
            let addedMinutes = Int(truncating: duration)
            let date = latestOverride.date ?? Date()
            let newDuration = max(
                Decimal(Date().distance(to: date.addingTimeInterval(addedMinutes.minutes.timeInterval)).minutes),
                0
            )
            let indefinite = latestOverride.indefinite
            var durationString = ""

            if !indefinite {
                if newDuration >= 1 {
                    durationString = formatHrMin(Int(newDuration))
                } else if newDuration > 0 {
                    durationString = "\(Int(newDuration * 60)) s"

                } else {
                    /// Do not show the Override anymore
                    Task {
                        guard let objectID = self.latestOverride.first?.objectID else { return }
                        await state.cancelOverride(withID: objectID)
                    }
                }
            }

            let smbScheduleString = latestOverride
                .smbIsScheduledOff && ((latestOverride.start?.stringValue ?? "") != (latestOverride.end?.stringValue ?? ""))
                ? " \(formatTimeRange(start: latestOverride.start?.stringValue, end: latestOverride.end?.stringValue))"
                : ""

            let smbToggleString = latestOverride.smbIsOff || latestOverride
                .smbIsScheduledOff ? "SMBs Off\(smbScheduleString)" : ""

            let components = [durationString, percentString, targetString, smbToggleString].filter { !$0.isEmpty }
            return components.isEmpty ? nil : components.joined(separator: ", ")
        }

        var tempTargetString: String? {
            guard let latestTempTarget = latestTempTarget.first else {
                return nil
            }
            let duration = latestTempTarget.duration
            let addedMinutes = Int(truncating: duration ?? 0)
            let date = latestTempTarget.date ?? Date()
            let newDuration = max(
                Decimal(Date().distance(to: date.addingTimeInterval(addedMinutes.minutes.timeInterval)).minutes),
                0
            )
            var durationString = ""
            var percentageString = ""
            var target = (latestTempTarget.target ?? 100) as Decimal
            var halfBasalTarget: Decimal = 160
            if latestTempTarget.halfBasalTarget != nil {
                halfBasalTarget = latestTempTarget.halfBasalTarget! as Decimal
            } else { halfBasalTarget = state.settingHalfBasalTarget }
            var showPercentage = false
            if target > 100, state.isExerciseModeActive || state.highTTraisesSens { showPercentage = true }
            if target < 100, state.lowTTlowersSens { showPercentage = true }
            if showPercentage {
                percentageString =
                    " \(state.computeAdjustedPercentage(halfBasalTargetValue: halfBasalTarget, tempTargetValue: target))%" }
            target = state.units == .mmolL ? target.asMmolL : target
            let targetString = target == 0 ? "" : (fetchedTargetFormatter.string(from: target as NSNumber) ?? "") + " " +
                state.units.rawValue + percentageString

            if newDuration >= 1 {
                durationString =
                    "\(newDuration.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))) min"
            } else if newDuration > 0 {
                durationString =
                    "\((newDuration * 60).formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))) s"
            } else {
                /// Do not show the Temp Target anymore
                Task {
                    guard let objectID = self.latestTempTarget.first?.objectID else { return }
                    await state.cancelTempTarget(withID: objectID)
                }
            }

            let components = [targetString, durationString].filter { !$0.isEmpty }
            return components.isEmpty ? nil : components.joined(separator: ", ")
        }

        var timeInterval: some View {
            HStack(alignment: .center) {
                ForEach(timeButtons) { button in
                    Text(button.active ? NSLocalizedString(button.label, comment: "") : button.number).onTapGesture {
                        state.hours = button.hours
                    }
                    .foregroundStyle(button.active ? (colorScheme == .dark ? Color.white : Color.black).opacity(0.9) : .secondary)
                    .frame(maxHeight: 30).padding(.horizontal, 8)
                    .background(
                        button.active ?
                            // RGB(30, 60, 95)
                            (
                                colorScheme == .dark ? Color(red: 0.1176470588, green: 0.2352941176, blue: 0.3725490196) :
                                    Color.white
                            ) :
                            Color
                            .clear
                    )
                    .cornerRadius(20)
                }
                Button(action: {
                    state.isLegendPresented.toggle()
                }) {
                    Image(systemName: "info")
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black).opacity(0.9)
                        .frame(width: 20, height: 20)
                        .background(
                            colorScheme == .dark ? Color(red: 0.1176470588, green: 0.2352941176, blue: 0.3725490196) :
                                Color.white
                        )
                        .clipShape(Circle())
                }
                .padding([.top, .bottom])
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.75 : 0.33),
                radius: colorScheme == .dark ? 5 : 3
            )
            .font(buttonFont)
        }

        @ViewBuilder func mainChart(geo: GeometryProxy) -> some View {
            ZStack {
                MainChartView(
                    geo: geo,
                    safeAreaSize: notificationsDisabled == true ? safeAreaSize : 0,
                    units: state.units,
                    hours: state.filteredHours,
                    tempTargets: state.tempTargets,
                    highGlucose: state.highGlucose,
                    lowGlucose: state.lowGlucose,
                    currentGlucoseTarget: state.currentGlucoseTarget,
                    glucoseColorScheme: state.glucoseColorScheme,
                    screenHours: state.hours,
                    displayXgridLines: state.displayXgridLines,
                    displayYgridLines: state.displayYgridLines,
                    thresholdLines: state.thresholdLines,
                    state: state
                )
            }
            .padding(.bottom, UIDevice.adjustPadding(min: 0, max: nil))
        }

        func highlightButtons() {
            for i in 0 ..< timeButtons.count {
                timeButtons[i].active = timeButtons[i].hours == state.hours
            }
        }

        @ViewBuilder func rightHeaderPanel(_: GeometryProxy) -> some View {
            VStack(alignment: .leading, spacing: 20) {
                /// Loop view at bottomLeading
                LoopView(
                    closedLoop: state.closedLoop,
                    timerDate: state.timerDate,
                    isLooping: state.isLooping,
                    lastLoopDate: state.lastLoopDate,
                    manualTempBasal: state.manualTempBasal,
                    determination: state.determinationsFromPersistence
                ).onTapGesture {
                    state.isStatusPopupPresented = true
                    setStatusTitle()
                }.onLongPressGesture {
                    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                    impactHeavy.impactOccurred()
                    state.runLoop()
                }
                /// eventualBG string at bottomTrailing

                if let eventualBG = state.enactedAndNonEnactedDeterminations.first?.eventualBG {
                    let bg = eventualBG as Decimal
                    HStack {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 16, weight: .bold))
                        Text(
                            Formatter.decimalFormatterWithTwoFractionDigits.string(
                                from: (
                                    state.units == .mmolL ? bg
                                        .asMmolL : bg
                                ) as NSNumber
                            )!
                        )
                        .font(.system(size: 16))
                    }
                } else {
                    HStack {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 16, weight: .bold))
                        Text("--")
                            .font(.system(size: 16))
                    }
                }
            }
        }

        @ViewBuilder func mealPanel(_: GeometryProxy) -> some View {
            HStack {
                HStack {
                    Image(systemName: "syringe.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color.insulin)
                    Text(
                        (
                            Formatter.decimalFormatterWithTwoFractionDigits
                                .string(from: (state.enactedAndNonEnactedDeterminations.first?.iob ?? 0) as NSNumber) ?? "0"
                        ) +
                            NSLocalizedString(" U", comment: "Insulin unit")
                    )
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                }

                Spacer()

                HStack {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 16))
                        .foregroundColor(.loopYellow)
                    Text(
                        (
                            Formatter.decimalFormatterWithTwoFractionDigits.string(
                                from: NSNumber(value: state.enactedAndNonEnactedDeterminations.first?.cob ?? 0)
                            ) ?? "0"
                        ) +
                            NSLocalizedString(" g", comment: "gram of carbs")
                    )
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                }

                Spacer()

                HStack {
                    if state.pumpSuspended {
                        Text("Pump suspended")
                            .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.loopGray)
                    } else if let tempBasalString = tempBasalString {
                        Image(systemName: "drop.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.insulinTintColor)
                        Text(tempBasalString)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    } else {
                        Image(systemName: "drop.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.insulinTintColor)
                        Text("No Data")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                }
                if state.totalInsulinDisplayType == .totalDailyDose {
                    Spacer()
                    Text(
                        "TDD: " +
                            (
                                Formatter.decimalFormatterWithTwoFractionDigits
                                    .string(from: (state.determinationsFromPersistence.first?.totalDailyDose ?? 0) as NSNumber) ??
                                    "0"
                            ) +
                            NSLocalizedString(" U", comment: "Insulin unit")
                    )
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                } else {
                    Spacer()
                    HStack {
                        Text(
                            "TINS: \(state.roundedTotalBolus)" +
                                NSLocalizedString(" U", comment: "Unit in number of units delivered (keep the space character!)")
                        )
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .onChange(of: state.hours) {
                            state.roundedTotalBolus = state.calculateTINS()
                        }
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                state.roundedTotalBolus = state.calculateTINS()
                            }
                        }
                    }
                }
            }.padding(.horizontal, 10)
        }

        @ViewBuilder func adjustmentsOverrideView(_ overrideString: String) -> some View {
            Group {
                Image(systemName: "clock.arrow.2.circlepath")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.primary, Color.purple)
                VStack(alignment: .leading) {
                    Text(latestOverride.first?.name ?? "Custom Override")
                        .font(.subheadline)
                        .frame(alignment: .leading)

                    Text(overrideString)
                        .font(.caption)
                }
            }
            .onTapGesture {
                selectedTab = 2
            }
        }

        @ViewBuilder func adjustmentsTempTargetView(_ tempTargetString: String) -> some View {
            Group {
                Image(systemName: "target")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.loopGreen)
                VStack(alignment: .leading) {
                    Text(latestTempTarget.first?.name ?? "Temp Target")
                        .font(.subheadline)
                    Text(tempTargetString)
                        .font(.caption)
                }
            }
            .onTapGesture {
                selectedTab = 2
            }
        }

        @ViewBuilder func adjustmentsCancelView(_ cancelAction: @escaping () -> Void) -> some View {
            Image(systemName: "xmark.app")
                .font(.system(size: 24))
                .onTapGesture {
                    cancelAction()
                }
        }

        @ViewBuilder func adjustmentsCancelTempTargetView() -> some View {
            Image(systemName: "xmark.app")
                .font(.system(size: 24))
                .confirmationDialog(
                    "Stop the Temp Target \"\(latestTempTarget.first?.name ?? "")\"?",
                    isPresented: $isConfirmStopTempTargetShown,
                    titleVisibility: .visible
                ) {
                    Button("Stop", role: .destructive) {
                        Task {
                            guard let objectID = latestTempTarget.first?.objectID else { return }
                            await state.cancelTempTarget(withID: objectID)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .padding(.trailing, 8)
                .onTapGesture {
                    if !latestTempTarget.isEmpty {
                        isConfirmStopTempTargetShown = true
                    }
                }
        }

        @ViewBuilder func adjustmentsCancelOverrideView() -> some View {
            Image(systemName: "xmark.app")
                .font(.system(size: 24))
                .confirmationDialog(
                    "Stop the Override \"\(latestOverride.first?.name ?? "")\"?",
                    isPresented: $isConfirmStopOverridePresented,
                    titleVisibility: .visible
                ) {
                    Button("Stop", role: .destructive) {
                        Task {
                            guard let objectID = latestOverride.first?.objectID else { return }
                            await state.cancelOverride(withID: objectID)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .padding(.trailing, 8)
                .onTapGesture {
                    if !latestOverride.isEmpty {
                        isConfirmStopOverridePresented = true
                    }
                }
        }

        @ViewBuilder func noActiveAdjustmentsView() -> some View {
            Group {
                VStack {
                    Text("No Active Adjustment")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Profile at 100 %")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.leading, 10)

                Spacer()

                /// to ensure the same position....
                Image(systemName: "xmark.app")
                    .font(.system(size: 25))
                    // clear color for the icon
                    .foregroundStyle(Color.clear)
            }.onTapGesture {
                selectedTab = 2
            }
        }

        @ViewBuilder func adjustmentView(geo: GeometryProxy) -> some View {
            ZStack {
                /// rectangle as background
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        (overrideString != nil || tempTargetString != nil) ?
                            (
                                colorScheme == .dark ?
                                    Color(red: 0.03921568627, green: 0.133333333, blue: 0.2156862745) :
                                    Color.insulin.opacity(0.1)
                            ) : Color.clear // Use clear and add the Material in the background
                    )
                    .background(.ultraThinMaterial.opacity(colorScheme == .dark ? 0.35 : 0))
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .frame(height: geo.size.height * 0.08)
                    .shadow(
                        color: (overrideString != nil || tempTargetString != nil) ?
                            (
                                colorScheme == .dark ? Color(red: 0.02745098039, green: 0.1098039216, blue: 0.1411764706) :
                                    Color.black.opacity(0.33)
                            ) : Color.clear,
                        radius: 3
                    )
                HStack {
                    if let overrideString = overrideString, let tempTargetString = tempTargetString {
                        HStack {
                            adjustmentsOverrideView(overrideString)

                            Spacer()

                            Divider()
                                .frame(height: geo.size.height * 0.05)
                                .padding(.horizontal, 2)

                            adjustmentsTempTargetView(tempTargetString)

                            Spacer()

                            adjustmentsCancelView({
                                if !latestTempTarget.isEmpty, !latestOverride.isEmpty {
                                    showCancelConfirmDialog = true
                                } else if !latestOverride.isEmpty {
                                    showCancelAlert = true
                                } else if !latestTempTarget.isEmpty {
                                    showCancelAlert = true
                                }
                            })
                        }
                    } else if let overrideString = overrideString {
                        adjustmentsOverrideView(overrideString)
                        Spacer()
                        adjustmentsCancelOverrideView()

                    } else if let tempTargetString = tempTargetString {
                        HStack {
                            adjustmentsTempTargetView(tempTargetString)
                            Spacer()
                            adjustmentsCancelTempTargetView()
                        }
                    } else {
                        noActiveAdjustmentsView()
                    }
                }.padding(.horizontal, 10)
                    .confirmationDialog("Adjustment to Stop", isPresented: $showCancelConfirmDialog) {
                        Button("Stop Override", role: .destructive) {
                            Task {
                                guard let objectID = latestOverride.first?.objectID else { return }
                                await state.cancelOverride(withID: objectID)
                            }
                        }
                        Button("Stop Temp Target", role: .destructive) {
                            Task {
                                guard let objectID = latestTempTarget.first?.objectID else { return }
                                await state.cancelTempTarget(withID: objectID)
                            }
                        }
                        Button("Stop All Adjustments", role: .destructive) {
                            Task {
                                guard let overrideObjectID = latestOverride.first?.objectID else { return }
                                await state.cancelOverride(withID: overrideObjectID)

                                guard let tempTargetObjectID = latestTempTarget.first?.objectID else { return }
                                await state.cancelTempTarget(withID: tempTargetObjectID)
                            }
                        }
                    } message: {
                        Text("Select Adjustment")
                    }
            }.padding(.horizontal, 10).padding(.bottom, UIDevice.adjustPadding(min: nil, max: 10))
        }

        @ViewBuilder func bolusProgressBar(_ progress: Decimal) -> some View {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 15)
                    .frame(height: 6)
                    .foregroundColor(.clear)
                    .background(
                        LinearGradient(colors: [
                            Color(red: 0.7215686275, green: 0.3411764706, blue: 1),
                            Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569),
                            Color(red: 0.4862745098, green: 0.5450980392, blue: 0.9529411765),
                            Color(red: 0.3411764706, green: 0.6666666667, blue: 0.9254901961),
                            Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902)
                        ], startPoint: .leading, endPoint: .trailing)
                            .mask(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 15)
                                    .frame(width: geo.size.width * CGFloat(progress))
                            }
                    )
            }
        }

        @ViewBuilder func bolusView(geo: GeometryProxy, _ progress: Decimal) -> some View {
            /// ensure that state.lastPumpBolus has a value, i.e. there is a last bolus done by the pump and not an external bolus
            /// - TRUE:  show the pump bolus
            /// - FALSE:  do not show a progress bar at all
            if let bolusTotal = state.lastPumpBolus?.bolus?.amount {
                let bolusFraction = progress * (bolusTotal as Decimal)
                let bolusString =
                    (bolusProgressFormatter.string(from: bolusFraction as NSNumber) ?? "0")
                        + " of " +
                        (Formatter.decimalFormatterWithTwoFractionDigits.string(from: bolusTotal as NSNumber) ?? "0")
                        + NSLocalizedString(" U", comment: "Insulin unit")

                ZStack {
                    /// rectangle as background
                    RoundedRectangle(cornerRadius: 15)
                        .fill(
                            colorScheme == .dark ? Color(red: 0.03921568627, green: 0.133333333, blue: 0.2156862745) : Color
                                .insulin
                                .opacity(0.2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                        .frame(height: geo.size.height * 0.08)
                        .shadow(
                            color: colorScheme == .dark ? Color(red: 0.02745098039, green: 0.1098039216, blue: 0.1411764706) :
                                Color.black.opacity(0.33),
                            radius: 3
                        )

                    /// actual bolus view
                    HStack {
                        Image(systemName: "cross.vial.fill")
                            .font(.system(size: 25))

                        Spacer()

                        VStack {
                            Text("Bolusing")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(bolusString)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.leading, 5)

                        Spacer()

                        Button {
                            state.showProgressView()
                            state.cancelBolus()
                        } label: {
                            Image(systemName: "xmark.app")
                                .font(.system(size: 25))
                        }
                    }.padding(.horizontal, 10)
                        .padding(.trailing, 8)

                }.padding(.horizontal, 10).padding(.bottom, UIDevice.adjustPadding(min: nil, max: 10))
                    .overlay(alignment: .bottom) {
                        // Use a geo-based offset here to position progress bar independent of device size
                        let offset = geo.size.height * 0.0725
                        bolusProgressBar(progress).padding(.horizontal, 18)
                            .offset(y: offset)
                    }.clipShape(RoundedRectangle(cornerRadius: 15))
            }
        }

        @ViewBuilder func alertSafetyNotificationsView(geo: GeometryProxy) -> some View {
            ZStack {
                /// rectangle as background
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        Color(
                            red: 0.9,
                            green: 0.133333333,
                            blue: 0.2156862745
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .frame(height: geo.size.height * safeAreaSize)
                    .coordinateSpace(name: "alertSafetyNotificationsView")
                    .shadow(
                        color: colorScheme == .dark ? Color(red: 0.02745098039, green: 0.1098039216, blue: 0.1411764706) :
                            Color.black.opacity(0.33),
                        radius: 3
                    )
                HStack {
                    Spacer()
                    VStack {
                        Text("⚠️ Safety Notifications are OFF")
                            .font(.headline)
                            .fontWeight(.bold)
                            .fontDesign(.rounded)
                            .foregroundStyle(.white.gradient)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Fix now by turning Notifications ON.")
                            .font(.footnote)
                            .fontDesign(.rounded)
                            .foregroundStyle(.white.gradient)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.leading, 5)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(.white)
                        .font(.headline)
                }.padding(.horizontal, 10)
                    .padding(.trailing, 8)
                    .onTapGesture {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    }
            }.padding(.horizontal, 10)
                .padding(.top, 0)
        }

        @ViewBuilder func mainViewElements(_ geo: GeometryProxy) -> some View {
            VStack(spacing: 0) {
                ZStack {
                    /// glucose bobble
                    glucoseView

                    /// right panel with loop status and evBG
                    HStack {
                        Spacer()
                        rightHeaderPanel(geo)
                    }.padding(.trailing, 20)

                    /// left panel with pump related info
                    HStack {
                        pumpView
                        Spacer()
                    }.padding(.leading, 20)
                }.padding(.top, 10)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if notificationsDisabled {
                            alertSafetyNotificationsView(geo: geo)
                        }
                    }

                mealPanel(geo).padding(.top, UIDevice.adjustPadding(min: nil, max: 30))
                    .padding(.bottom, UIDevice.adjustPadding(min: nil, max: 20))

                mainChart(geo: geo)

                timeInterval.padding(.top, UIDevice.adjustPadding(min: 0, max: 12))
                    .padding(.bottom, UIDevice.adjustPadding(min: 0, max: 12))

                if let progress = state.bolusProgress {
                    bolusView(geo: geo, progress)
                        .padding(.bottom, UIDevice.adjustPadding(min: nil, max: 40))
                } else {
                    adjustmentView(geo: geo).padding(.bottom, UIDevice.adjustPadding(min: nil, max: 40))
                }
            }
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onReceive(
                resolver.resolve(AlertPermissionsChecker.self)!.$notificationsDisabled,
                perform: {
                    if notificationsDisabled != $0 {
                        notificationsDisabled = $0
                        if notificationsDisabled {
                            debug(.default, "notificationsDisabled")
                        }
                    }
                }
            )
        }

        @ViewBuilder func mainView() -> some View {
            GeometryReader { geo in
                mainViewElements(geo)
            }
            .onChange(of: state.hours) {
                highlightButtons()
            }
            .onAppear {
                configureView {
                    highlightButtons()
                }
            }
            .navigationTitle("Home")
            .navigationBarHidden(true)
            .ignoresSafeArea(.keyboard)
            .popup(isPresented: state.isStatusPopupPresented, alignment: .top, direction: .top) {
                popup
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(colorScheme == .dark ? Color(
                                "Chart"
                            ) : Color(UIColor.darkGray))
                    )
                    .onTapGesture {
                        state.isStatusPopupPresented = false
                    }
                    .gesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .local)
                            .onEnded { value in
                                if value.translation.height < 0 {
                                    state.isStatusPopupPresented = false
                                }
                            }
                    )
            }
            .confirmationDialog("Pump Model", isPresented: $showPumpSelection) {
                Button("Medtronic") { state.addPump(.minimed) }
                Button("Omnipod Eros") { state.addPump(.omnipod) }
                Button("Omnipod Dash") { state.addPump(.omnipodBLE) }
                Button("Dana(RS/-i)") { state.addPump(.dana) }
                Button("Pump Simulator") { state.addPump(.simulator) }
            } message: { Text("Select Pump Model") }
            .sheet(isPresented: $state.setupPump) {
                if let pumpManager = state.provider.apsManager.pumpManager {
                    PumpConfig.PumpSettingsView(
                        pumpManager: pumpManager,
                        bluetoothManager: state.provider.apsManager.bluetoothManager!,
                        completionDelegate: state,
                        setupDelegate: state
                    )
                } else {
                    PumpConfig.PumpSetupView(
                        pumpType: state.setupPumpType,
                        pumpInitialSettings: PumpConfig.PumpInitialSettings.default,
                        bluetoothManager: state.provider.apsManager.bluetoothManager!,
                        completionDelegate: state,
                        setupDelegate: state
                    )
                }
            }
            .sheet(isPresented: $state.isLegendPresented) {
                ChartLegendView(state: state)
            }
        }

        @ViewBuilder func tabBar() -> some View {
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedTab) {
                    let carbsRequiredBadge: String? = {
                        guard let carbsRequired = state.enactedAndNonEnactedDeterminations.first?.carbsRequired,
                              state.showCarbsRequiredBadge
                        else {
                            return nil
                        }
                        let carbsRequiredDecimal = Decimal(carbsRequired)
                        if carbsRequiredDecimal > state.settingsManager.settings.carbsRequiredThreshold {
                            let numberAsNSNumber = NSDecimalNumber(decimal: carbsRequiredDecimal)
                            return (Formatter.decimalFormatterWithTwoFractionDigits.string(from: numberAsNSNumber) ?? "") + " g"
                        }
                        return nil
                    }()

                    NavigationStack { mainView() }
                        .tabItem { Label("Main", systemImage: "chart.xyaxis.line") }
                        .badge(carbsRequiredBadge).tag(0)

                    NavigationStack { DataTable.RootView(resolver: resolver) }
                        .tabItem { Label("History", systemImage: historySFSymbol) }.tag(1)

                    Spacer()

                    NavigationStack { Adjustments.RootView(resolver: resolver) }
                        .tabItem {
                            Label(
                                "Adjustments",
                                systemImage: "slider.horizontal.2.gobackward"
                            ) }.tag(2)

                    NavigationStack(path: self.$settingsPath) {
                        Settings.RootView(resolver: resolver) }
                        .tabItem { Label(
                            "Settings",
                            systemImage: "gear"
                        ) }.tag(3)
                }
                .tint(Color.tabBar)

                Button(
                    action: {
                        state.showModal(for: .bolus) },
                    label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.tabBar)
                            .padding(.bottom, 1)
                            .padding(.horizontal, 22.5)
                    }
                )
            }.ignoresSafeArea(.keyboard, edges: .bottom).blur(radius: state.waitForSuggestion ? 8 : 0)
                .onChange(of: selectedTab) {
                    print("current path is empty: \(settingsPath.isEmpty)")
                    settingsPath = NavigationPath()
                }
        }

        var body: some View {
            ZStack(alignment: .center) {
                tabBar()

                if state.waitForSuggestion {
                    CustomProgressView(text: "Updating IOB...")
                }
            }
        }

        // TODO: Consolidate all mmol parsing methods (in TagCloudView, NightscoutManager and HomeRootView) to one central func
        private func parseReasonConclusion(_ reasonConclusion: String, isMmolL: Bool) -> String {
            let patterns = [
                "minGuardBG\\s*-?\\d+\\.?\\d*<-?\\d+\\.?\\d*",
                "Eventual BG\\s*-?\\d+\\.?\\d*\\s*>=\\s*-?\\d+\\.?\\d*",
                "(\\S+)\\s+(-?\\d+\\.?\\d*)\\s*>\\s*(\\d+)%\\s+of\\s+BG\\s+(-?\\d+\\.?\\d*)" // "for case maxDelta 37 > 20% of BG 95"
            ]
            let pattern = patterns.joined(separator: "|")
            let regex = try! NSRegularExpression(pattern: pattern)

            func convertToMmolL(_ value: String) -> String {
                if let glucoseValue = Double(value.replacingOccurrences(of: "[^\\d.-]", with: "", options: .regularExpression)) {
                    let mmolValue = Decimal(glucoseValue).asMmolL
                    return mmolValue.description
                }
                return value
            }

            let matches = regex.matches(
                in: reasonConclusion,
                range: NSRange(reasonConclusion.startIndex..., in: reasonConclusion)
            )
            var updatedConclusion = reasonConclusion

            for match in matches.reversed() {
                guard let range = Range(match.range, in: reasonConclusion) else { continue }
                let matchedString = String(reasonConclusion[range])

                if isMmolL {
                    // Handle "minGuardBG x<y" pattern
                    if matchedString.contains("<") {
                        let parts = matchedString.components(separatedBy: "<")
                        if parts.count == 2 {
                            let firstValue = parts[0].trimmingCharacters(in: .whitespaces)
                            let secondValue = parts[1].trimmingCharacters(in: .whitespaces)
                            let formattedFirstValue = convertToMmolL(firstValue)
                            let formattedSecondValue = convertToMmolL(secondValue)
                            let formattedString = "minGuardBG \(formattedFirstValue)<\(formattedSecondValue)"
                            updatedConclusion.replaceSubrange(range, with: formattedString)
                        }
                    }
                    // Handle "Eventual BG x >= target" pattern
                    else if matchedString.contains(">=") {
                        let parts = matchedString.components(separatedBy: " >= ")
                        if parts.count == 2 {
                            let firstValue = parts[0].trimmingCharacters(in: .whitespaces)
                            let secondValue = parts[1].trimmingCharacters(in: .whitespaces)
                            let formattedFirstValue = convertToMmolL(firstValue)
                            let formattedSecondValue = convertToMmolL(secondValue)
                            let formattedString = "Eventual BG \(formattedFirstValue) >= \(formattedSecondValue)"
                            updatedConclusion.replaceSubrange(range, with: formattedString)
                        }
                    }
                    // Handle "maxDelta 37 > 20% of BG 95" style
                    else if let localMatch = regex.firstMatch(
                        in: matchedString,
                        range: NSRange(matchedString.startIndex..., in: matchedString)
                    ) {
                        if match.numberOfRanges == 5 {
                            let metric = String(matchedString[Range(localMatch.range(at: 1), in: matchedString)!])
                            let firstValue = String(matchedString[Range(localMatch.range(at: 2), in: matchedString)!])
                            let percentage = String(matchedString[Range(localMatch.range(at: 3), in: matchedString)!])
                            let bgValue = String(matchedString[Range(localMatch.range(at: 4), in: matchedString)!])

                            let formattedFirstValue = convertToMmolL(firstValue)
                            let formattedBGValue = convertToMmolL(bgValue)

                            let formattedString = "\(metric) \(formattedFirstValue) > \(percentage)% of BG \(formattedBGValue)"
                            updatedConclusion.replaceSubrange(range, with: formattedString)
                        }
                    }
                } else {
                    // When isMmolL is false, ensure the original value is retained without any duplication
                    updatedConclusion.replaceSubrange(range, with: matchedString)
                }
            }

            return updatedConclusion.capitalizingFirstLetter()
        }

        private var popup: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle).font(.headline).foregroundColor(.white)
                    .padding(.bottom, 4)
                if let determination = state.determinationsFromPersistence.first {
                    if determination.glucose == 400 {
                        Text("Invalid CGM reading (HIGH).").font(.callout).bold().foregroundColor(.loopRed).padding(.top, 8)
                        Text("SMBs and High Temps Disabled.").font(.caption).foregroundColor(.white).padding(.bottom, 4)
                    } else {
                        let tags = !state.isSmoothingEnabled ? determination.reasonParts : determination
                            .reasonParts + ["Smoothing: On"]
                        TagCloudView(
                            tags: tags,
                            shouldParseToMmolL: state.units == .mmolL
                        )
                        .animation(.none, value: false)

                        Text(
                            self
                                .parseReasonConclusion(
                                    determination.reasonConclusion,
                                    isMmolL: state.units == .mmolL
                                )
                        ).font(.caption).foregroundColor(.white)
                    }
                } else {
                    Text("No determination found").font(.body).foregroundColor(.white)
                }

                if let errorMessage = state.errorMessage, let date = state.errorDate {
                    Text(NSLocalizedString("Error at", comment: "") + " " + Formatter.dateFormatter.string(from: date))
                        .foregroundColor(.white)
                        .font(.headline)
                        .padding(.bottom, 4)
                        .padding(.top, 8)
                    Text(errorMessage).font(.caption).foregroundColor(.loopRed)
                }
            }
        }

        private func setStatusTitle() {
            if let determination = state.determinationsFromPersistence.first {
                let dateFormatter = DateFormatter()
                dateFormatter.timeStyle = .short
                statusTitle = NSLocalizedString("Oref Determination enacted at", comment: "Headline in enacted pop up") +
                    " " +
                    dateFormatter
                    .string(from: determination.deliverAt ?? Date())
            } else {
                statusTitle = "No Oref determination"
                return
            }
        }
    }
}

extension UIDevice {
    public enum DeviceSize: CGFloat {
        case smallDevice = 667 // Height for 4" iPhone SE
        case largeDevice = 852 // Height for 6.1" iPhone 15 Pro
    }

    @usableFromInline static func adjustPadding(
        min: CGFloat? = nil,
        max: CGFloat? = nil
    ) -> CGFloat? {
        if UIScreen.screenHeight > UIDevice.DeviceSize.smallDevice.rawValue {
            if UIScreen.screenHeight >= UIDevice.DeviceSize.largeDevice.rawValue {
                return max
            } else {
                return min != nil ?
                    (max != nil ? max! * (UIScreen.screenHeight / UIDevice.DeviceSize.largeDevice.rawValue) : nil) : nil
            }
        } else {
            return min
        }
    }
}

extension UIScreen {
    static var screenHeight: CGFloat {
        UIScreen.main.bounds.height
    }

    static var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }
}

/// Checks if the device is using a 24-hour time format.
func is24HourFormat() -> Bool {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    let dateString = formatter.string(from: Date())

    return !dateString.contains("AM") && !dateString.contains("PM")
}

/// Converts a duration in minutes to a formatted string (e.g., "1 hr 30 min").
func formatHrMin(_ durationInMinutes: Int) -> String {
    let hours = durationInMinutes / 60
    let minutes = durationInMinutes % 60

    switch (hours, minutes) {
    case let (0, m):
        return "\(m) min"
    case let (h, 0):
        return "\(h) hr"
    default:
        return "\(hours) hr \(minutes) min"
    }
}

// Helper function to convert a start and end hour to either 24-hour or AM/PM format
func formatTimeRange(start: String?, end: String?) -> String {
    guard let start = start, let end = end else {
        return ""
    }

    // Check if the format is 24-hour or AM/PM
    if is24HourFormat() {
        // Return the original 24-hour format
        return "\(start)-\(end)"
    } else {
        // Convert to AM/PM format using DateFormatter
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"

        if let startHour = Int(start), let endHour = Int(end) {
            let startDate = Calendar.current.date(bySettingHour: startHour, minute: 0, second: 0, of: Date()) ?? Date()
            let endDate = Calendar.current.date(bySettingHour: endHour, minute: 0, second: 0, of: Date()) ?? Date()

            // Customize the format to "2p" or "2a"
            formatter.dateFormat = "ha"
            let startFormatted = formatter.string(from: startDate).lowercased().replacingOccurrences(of: "m", with: "")
            let endFormatted = formatter.string(from: endDate).lowercased().replacingOccurrences(of: "m", with: "")

            return "\(startFormatted)-\(endFormatted)"
        } else {
            return ""
        }
    }
}
