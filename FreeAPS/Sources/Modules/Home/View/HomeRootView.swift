import CoreData
import SpriteKit
import SwiftDate
import SwiftUI
import Swinject

extension Home {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()
        @State var isStatusPopupPresented = false
        @State var showCancelAlert = false
        @State var isMenuPresented = false
        @State var showTreatments = false
        @State var selectedTab: Int = 0
        @State private var statusTitle: String = ""

        struct Buttons: Identifiable {
            let label: String
            let number: String
            var active: Bool
            let hours: Int16
            var id: String { label }
        }

        @State var timeButtons: [Buttons] = [
            Buttons(label: "2 hours", number: "2", active: false, hours: 2),
            Buttons(label: "4 hours", number: "4", active: false, hours: 4),
            Buttons(label: "6 hours", number: "6", active: false, hours: 6),
            Buttons(label: "12 hours", number: "12", active: false, hours: 12),
            Buttons(label: "24 hours", number: "24", active: false, hours: 24)
        ]

        let buttonFont = Font.custom("TimeButtonFont", size: 14)

        @Environment(\.managedObjectContext) var moc
        @Environment(\.colorScheme) var colorScheme

        @FetchRequest(
            entity: Override.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var fetchedPercent: FetchedResults<Override>

        @FetchRequest(
            fetchRequest: OrefDetermination.fetch(NSPredicate.enactedDetermination),
            animation: .bouncy
        ) var determination: FetchedResults<OrefDetermination>

        @FetchRequest(
            fetchRequest: PumpEventStored.fetch(NSPredicate.recentPumpHistory, ascending: false, fetchLimit: 1),
            animation: .bouncy
        ) var recentPumpHistory: FetchedResults<PumpEventStored>

        @FetchRequest(
            entity: OverridePresets.entity(),
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)], predicate: NSPredicate(
                format: "name != %@", "" as String
            )
        ) var fetchedProfiles: FetchedResults<OverridePresets>

        @FetchRequest(
            entity: TempTargets.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var sliderTTpresets: FetchedResults<TempTargets>

        @FetchRequest(
            entity: TempTargetsSlider.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var enactedSliderTT: FetchedResults<TempTargetsSlider>

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

        private var numberFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
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

        private var targetFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        private var tirFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        private var dateFormatter: DateFormatter {
            let dateFormatter = DateFormatter()
            dateFormatter.timeStyle = .short
            return dateFormatter
        }

        private var spriteScene: SKScene {
            let scene = SnowScene()
            scene.scaleMode = .resizeFill
            scene.backgroundColor = .clear
            return scene
        }

        private var color: LinearGradient {
            colorScheme == .dark ? LinearGradient(
                gradient: Gradient(colors: [
                    Color.bgDarkBlue,
                    Color.bgDarkerDarkBlue
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
                :
                LinearGradient(
                    gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
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
                timerDate: $state.timerDate,
                units: $state.units,
                alarm: $state.alarm,
                lowGlucose: $state.lowGlucose,
                highGlucose: $state.highGlucose
            ).scaleEffect(0.9)
                .onTapGesture {
                    if state.alarm == nil {
                        state.openCGM()
                    } else {
                        state.showModal(for: .snooze)
                    }
                }
                .onLongPressGesture {
                    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                    impactHeavy.impactOccurred()
                    if state.alarm == nil {
                        state.showModal(for: .snooze)
                    } else {
                        state.openCGM()
                    }
                }
        }

        var pumpView: some View {
            PumpView(
                reservoir: $state.reservoir,
                name: $state.pumpName,
                expiresAtDate: $state.pumpExpiresAtDate,
                timerDate: $state.timerDate,
                timeZone: $state.timeZone,
                state: state
            ).onTapGesture {
                if state.pumpDisplayState != nil {
                    state.setupPump = true
                }
            }
        }

        var tempBasalString: String? {
            guard let tempRate = recentPumpHistory.first?.tempBasal?.rate else {
                return nil
            }
            let rateString = numberFormatter.string(from: tempRate as NSNumber) ?? "0"
            var manualBasalString = ""

            if let apsManager = state.apsManager, apsManager.isManualTempBasal {
                manualBasalString = NSLocalizedString(
                    " - Manual Basal ⚠️",
                    comment: "Manual Temp basal"
                )
            }

            return rateString + " " + NSLocalizedString(" U/hr", comment: "Unit per hour with space") + manualBasalString
        }

        var tempTargetString: String? {
            guard let tempTarget = state.tempTarget else {
                return nil
            }
            let target = tempTarget.targetBottom ?? 0
            let unitString = targetFormatter.string(from: (tempTarget.targetBottom?.asMmolL ?? 0) as NSNumber) ?? ""
            let rawString = (tirFormatter.string(from: (tempTarget.targetBottom ?? 0) as NSNumber) ?? "") + " " + state.units
                .rawValue

            var string = ""
            if sliderTTpresets.first?.active ?? false {
                let hbt = sliderTTpresets.first?.hbt ?? 0
                string = ", " + (tirFormatter.string(from: state.infoPanelTTPercentage(hbt, target) as NSNumber) ?? "") + " %"
            }

            let percentString = state
                .units == .mmolL ? (unitString + " mmol/L" + string) : (rawString + (string == "0" ? "" : string))
            return tempTarget.displayName + " " + percentString
        }

        var overrideString: String? {
            guard fetchedPercent.first?.enabled ?? false else {
                return nil
            }
            var percentString = "\((fetchedPercent.first?.percentage ?? 100).formatted(.number)) %"
            var target = (fetchedPercent.first?.target ?? 100) as Decimal
            let indefinite = (fetchedPercent.first?.indefinite ?? false)
            let unit = state.units.rawValue
            if state.units == .mmolL {
                target = target.asMmolL
            }
            var targetString = (fetchedTargetFormatter.string(from: target as NSNumber) ?? "") + " " + unit
            if tempTargetString != nil || target == 0 { targetString = "" }
            percentString = percentString == "100 %" ? "" : percentString

            let duration = (fetchedPercent.first?.duration ?? 0) as Decimal
            let addedMinutes = Int(duration)
            let date = fetchedPercent.first?.date ?? Date()
            var newDuration: Decimal = 0

            if date.addingTimeInterval(addedMinutes.minutes.timeInterval) > Date() {
                newDuration = Decimal(Date().distance(to: date.addingTimeInterval(addedMinutes.minutes.timeInterval)).minutes)
            }

            var durationString = indefinite ?
                "" : newDuration >= 1 ?
                (newDuration.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) + " min") :
                (
                    newDuration > 0 ? (
                        (newDuration * 60).formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) + " s"
                    ) :
                        ""
                )

            let smbToggleString = (fetchedPercent.first?.smbIsOff ?? false) ? " \u{20e0}" : ""
            var comma1 = ", "
            var comma2 = comma1
            var comma3 = comma1
            if targetString == "" || percentString == "" { comma1 = "" }
            if durationString == "" { comma2 = "" }
            if smbToggleString == "" { comma3 = "" }

            if percentString == "", targetString == "" {
                comma1 = ""
                comma2 = ""
            }
            if percentString == "", targetString == "", smbToggleString == "" {
                durationString = ""
                comma1 = ""
                comma2 = ""
                comma3 = ""
            }
            if durationString == "" {
                comma2 = ""
            }
            if smbToggleString == "" {
                comma3 = ""
            }

            if durationString == "", !indefinite {
                return nil
            }
            return percentString + comma1 + targetString + comma2 + durationString + comma3 + smbToggleString
        }

        var infoPanel: some View {
            HStack(alignment: .center) {
                if state.pumpSuspended {
                    Text("Pump suspended")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(.loopGray)
                        .padding(.leading, 8)
                } else if let tempBasalString = tempBasalString {
                    Text(tempBasalString)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.insulin)
                        .padding(.leading, 8)
                }
                if state.tins {
                    Text(
                        "TINS: \(state.calculateTINS())" +
                            NSLocalizedString(" U", comment: "Unit in number of units delivered (keep the space character!)")
                    )
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.insulin)
                }

                if let tempTargetString = tempTargetString {
                    Text(tempTargetString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if state.closedLoop, state.settingsManager.preferences.maxIOB == 0 {
                    Text("Max IOB: 0").font(.callout).foregroundColor(.orange).padding(.trailing, 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 30)
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
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.75 : 0.33),
                radius: colorScheme == .dark ? 5 : 3
            )
            .font(buttonFont)
        }

        var mainChart: some View {
            ZStack {
                if state.animatedBackground {
                    SpriteView(scene: spriteScene, options: [.allowsTransparency])
                        .ignoresSafeArea()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                }

                MainChartView(
                    units: $state.units,
                    tempBasals: $state.tempBasals,
                    boluses: $state.boluses,
                    suspensions: $state.suspensions,
                    announcement: $state.announcement,
                    hours: .constant(state.filteredHours),
                    maxBasal: $state.maxBasal,
                    autotunedBasalProfile: $state.autotunedBasalProfile,
                    basalProfile: $state.basalProfile,
                    tempTargets: $state.tempTargets,
                    smooth: $state.smooth,
                    highGlucose: $state.highGlucose,
                    lowGlucose: $state.lowGlucose,
                    screenHours: $state.hours,
                    displayXgridLines: $state.displayXgridLines,
                    displayYgridLines: $state.displayYgridLines,
                    thresholdLines: $state.thresholdLines,
                    isTempTargetActive: $state.isTempTargetActive, state: state
                )
            }
            .padding(.bottom)
        }

        private func selectedProfile() -> (name: String, isOn: Bool) {
            var profileString = ""
            var display: Bool = false

            let duration = (fetchedPercent.first?.duration ?? 0) as Decimal
            let indefinite = fetchedPercent.first?.indefinite ?? false
            let addedMinutes = Int(duration)
            let date = fetchedPercent.first?.date ?? Date()
            if date.addingTimeInterval(addedMinutes.minutes.timeInterval) > Date() || indefinite {
                display.toggle()
            }

            if fetchedPercent.first?.enabled ?? false, !(fetchedPercent.first?.isPreset ?? false), display {
                profileString = NSLocalizedString("Custom Profile", comment: "Custom but unsaved Profile")
            } else if !(fetchedPercent.first?.enabled ?? false) || !display {
                profileString = NSLocalizedString("Normal Profile", comment: "Your normal Profile. Use a short string")
            } else {
                let id_ = fetchedPercent.first?.id ?? ""
                let profile = fetchedProfiles.filter({ $0.id == id_ }).first
                if profile != nil {
                    profileString = profile?.name?.description ?? ""
                }
            }
            return (name: profileString, isOn: display)
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
                    closedLoop: $state.closedLoop,
                    timerDate: $state.timerDate,
                    isLooping: $state.isLooping,
                    lastLoopDate: $state.lastLoopDate,
                    manualTempBasal: $state.manualTempBasal
                ).onTapGesture {
                    state.isStatusPopupPresented = true
                    setStatusTitle()
                }.onLongPressGesture {
                    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                    impactHeavy.impactOccurred()
                    state.runLoop()
                }
                /// eventualBG string at bottomTrailing

                if let eventualBG = determination.first?.eventualBG {
                    let bg = eventualBG as Decimal
                    HStack {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 16, weight: .bold))
                        Text(
                            numberFormatter.string(
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
//                if let eventualBG = state.eventualBG {
//                    HStack {
//                        Image(systemName: "arrow.right.circle")
//                            .font(.system(size: 16, weight: .bold))
//                        Text(
//                            numberFormatter.string(
//                                from: (
//                                    state.units == .mmolL ? eventualBG
//                                        .asMmolL : Decimal(eventualBG)
//                                ) as NSNumber
//                            )!
//                        )
//                        .font(.system(size: 16))
//                    }
//                }
            }
        }

        @ViewBuilder func mealPanel(_: GeometryProxy) -> some View {
            HStack {
                HStack {
                    Image(systemName: "syringe.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color.insulin)
                    Text(
                        (numberFormatter.string(from: (determination.first?.iob ?? 0) as NSNumber) ?? "0") +
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
                        (numberFormatter.string(from: (determination.first?.cob ?? 0) as NSNumber) ?? "0") +
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
                    }
                }
                if !state.tins {
                    Spacer()
                    Text(
                        "TDD: " +
                            (
                                numberFormatter
                                    .string(from: (determination.first?.totalDailyDose ?? 0) as NSNumber) ?? "0"
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
                        .onChange(of: state.hours) { _ in
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

        @ViewBuilder func profileView(_: GeometryProxy) -> some View {
            ZStack {
                /// rectangle as background
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        colorScheme == .dark ? Color(red: 0.03921568627, green: 0.133333333, blue: 0.2156862745) : Color.insulin
                            .opacity(0.1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .frame(height: UIScreen.main.bounds.height / 18)
                    .shadow(
                        color: colorScheme == .dark ? Color(red: 0.02745098039, green: 0.1098039216, blue: 0.1411764706) :
                            Color.black.opacity(0.33),
                        radius: 3
                    )
                HStack {
                    /// actual profile view
                    Image(systemName: "person.fill")
                        .font(.system(size: 25))

                    Spacer()

                    if let overrideString = overrideString {
                        VStack {
                            Text(selectedProfile().name)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(overrideString)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.leading, 5)
                        Spacer()
                        Image(systemName: "xmark.app")
                            .font(.system(size: 25))
                    } else {
                        if tempTargetString == nil {
                            VStack {
                                Text(selectedProfile().name)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("100 %")
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(.leading, 5)
                            Spacer()
                            /// to ensure the same position....
                            Image(systemName: "xmark.app")
                                .font(.system(size: 25))
                                .foregroundStyle(Color.clear)
                        }
                    }
                }.padding(.horizontal, 10)
                    .alert(
                        "Return to Normal?", isPresented: $showCancelAlert,
                        actions: {
                            Button("No", role: .cancel) {}
                            Button("Yes", role: .destructive) {
                                state.cancelProfile()
                            }
                        }, message: { Text("This will change settings back to your normal profile.") }
                    )
                    .padding(.trailing, 8)
                    .onTapGesture {
                        if selectedProfile().name != "Normal Profile" {
                            showCancelAlert = true
                        }
                    }
            }.padding(.horizontal, 10).padding(.bottom, 10)
                .overlay {
                    /// just show temp target if no profile is already active
                    if overrideString == nil, let tempTargetString = tempTargetString {
                        ZStack {
                            /// rectangle as background
                            RoundedRectangle(cornerRadius: 15)
                                .fill(
                                    colorScheme == .dark ? Color(red: 0.03921568627, green: 0.133333333, blue: 0.2156862745) :
                                        Color
                                        .insulin
                                        .opacity(0.2)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 15))
                                .frame(height: UIScreen.main.bounds.height / 18)
                                .shadow(
                                    color: colorScheme == .dark ? Color(
                                        red: 0.02745098039,
                                        green: 0.1098039216,
                                        blue: 0.1411764706
                                    ) :
                                        Color.black.opacity(0.33),
                                    radius: 3
                                )
                            HStack {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 25))
                                Spacer()
                                Text(tempTargetString)
                                    .font(.subheadline)
                                Spacer()
                            }.padding(.horizontal, 10)
                        }.padding(.horizontal, 10).padding(.bottom, 10)
                    }
                }
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

        @ViewBuilder func bolusView(_: GeometryProxy, _ progress: Decimal) -> some View {
            let bolusTotal = (recentPumpHistory.first?.bolus?.amount) as? Decimal ?? 0
            let bolusFraction = progress * bolusTotal

            let bolusString =
                (bolusProgressFormatter.string(from: bolusFraction as NSNumber) ?? "0")
                    + " of " +
                    (numberFormatter.string(from: bolusTotal as NSNumber) ?? "0")
                    + NSLocalizedString(" U", comment: "Insulin unit")

            ZStack {
                /// rectangle as background
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        colorScheme == .dark ? Color(red: 0.03921568627, green: 0.133333333, blue: 0.2156862745) : Color.insulin
                            .opacity(0.2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .frame(height: UIScreen.main.bounds.height / 18)
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
                        state.waitForSuggestion = true
                        state.cancelBolus()
                    } label: {
                        Image(systemName: "xmark.app")
                            .font(.system(size: 25))
                    }
                }.padding(.horizontal, 10)
                    .padding(.trailing, 8)

            }.padding(.horizontal, 10).padding(.bottom, 10)
                .overlay(alignment: .bottom) {
                    bolusProgressBar(progress).padding(.horizontal, 18).offset(y: 45)
                }.clipShape(RoundedRectangle(cornerRadius: 15))
        }

        @ViewBuilder func mainView() -> some View {
            GeometryReader { geo in
                VStack(spacing: 0) {
//                    Spacer()
//                        .frame(height: UIScreen.main.bounds.height / 40)

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

                    mealPanel(geo).padding(.top, 30).padding(.bottom, 20)

                    mainChart

                    timeInterval.padding(.top, 20).padding(.bottom, 40)

                    if let progress = state.bolusProgress {
                        bolusView(geo, progress).padding(.bottom, 10)
                    } else {
                        profileView(geo).padding(.bottom, 10)
                    }
                }
                .background(color)
            }
            .onChange(of: state.hours) { _ in
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
        }

        @ViewBuilder func tabBar() -> some View {
            ZStack(alignment: .bottom) {
                TabView {
                    let carbsRequiredBadge: String? = {
                        guard let carbsRequired = determination.first?.carbsRequired as? Decimal else { return nil }
                        if carbsRequired > state.settingsManager.settings.carbsRequiredThreshold {
                            let numberAsNSNumber = NSDecimalNumber(decimal: carbsRequired)
                            let formattedNumber = numberFormatter.string(from: numberAsNSNumber) ?? ""
                            return formattedNumber + " g"
                        } else {
                            return nil
                        }
                    }()

                    NavigationStack { mainView() }
                        .tabItem { Label("Main", systemImage: "chart.xyaxis.line") }
                        .badge(carbsRequiredBadge)

                    NavigationStack { DataTable.RootView(resolver: resolver) }
                        .tabItem { Label("History", systemImage: historySFSymbol) }

                    Spacer()

                    NavigationStack { OverrideProfilesConfig.RootView(resolver: resolver) }
                        .tabItem {
                            Label(
                                "Profile",
                                systemImage: "person.fill"
                            ) }

                    NavigationStack { Settings.RootView(resolver: resolver) }
                        .tabItem {
                            Label(
                                "Menu",
                                systemImage: "text.justify"
                            ) }
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
                            .padding(.horizontal, 20)
                    }
                )
            }.ignoresSafeArea(.keyboard, edges: .bottom).blur(radius: state.waitForSuggestion ? 8 : 0)
        }

        var body: some View {
            ZStack(alignment: .center) {
                tabBar()

                if state.waitForSuggestion {
                    CustomProgressView(text: "Updating IOB...")
                }
            }
        }

        private var popup: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle).font(.headline).foregroundColor(.white)
                    .padding(.bottom, 4)
                if let determination = determination.first {
                    if determination.glucose == 400 {
                        Text("Invalid CGM reading (HIGH).").font(.callout).bold().foregroundColor(.loopRed).padding(.top, 8)
                        Text("SMBs and High Temps Disabled.").font(.caption).foregroundColor(.white).padding(.bottom, 4)
                    } else {
                        TagCloudView(tags: determination.reasonParts).animation(.none, value: false)

                        Text(determination.reasonConclusion.capitalizingFirstLetter()).font(.caption).foregroundColor(.white)
                    }
                } else {
                    Text("No determination found").font(.body).foregroundColor(.white)
                }

                if let errorMessage = state.errorMessage, let date = state.errorDate {
                    Text(NSLocalizedString("Error at", comment: "") + " " + dateFormatter.string(from: date))
                        .foregroundColor(.white)
                        .font(.headline)
                        .padding(.bottom, 4)
                        .padding(.top, 8)
                    Text(errorMessage).font(.caption).foregroundColor(.loopRed)
                }
            }
        }

        private func setStatusTitle() {
            if let determination = determination.first {
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
