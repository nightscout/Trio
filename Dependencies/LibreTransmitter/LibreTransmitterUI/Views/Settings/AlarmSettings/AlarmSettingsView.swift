//
//  AlarmSettingsView.swift
//  LibreTransmitterUI
//
//  Created by LoopKit Authors on 11/05/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import HealthKit

private func systemImage(_ name:String) -> some View {
    Image(systemName: name)
         .resizable()
         .interpolation(.high)
         .scaledToFit()
         .frame(width: 40)
}

class AlarmScheduleState: ObservableObject, Identifiable, Hashable {

    var id = UUID()

    @Published var lowmgdl: Double = 72
    @Published var highmgdl: Double = 180
    @Published var enabled: Bool? = false

    @Published var alarmDateComponents: AlarmTimeCellExternalState = AlarmTimeCellExternalState()

    public func setLowAlarm(forUnit unit: HKUnit, lowAlarm: Double) {

        if unit == HKUnit.millimolesPerLiter {
            self.lowmgdl = lowAlarm * 18
            return
        }

        self.lowmgdl = lowAlarm
    }

    public func getLowAlarm(forUnit unit: HKUnit) -> Double {

        if unit == HKUnit.millimolesPerLiter {
            return (lowmgdl / 18).roundTo(places: 1)
        }

        return lowmgdl

    }

    public func setHighAlarm(forUnit unit: HKUnit, highAlarm: Double) {

        if unit == HKUnit.millimolesPerLiter {
            self.highmgdl = highAlarm * 18
            return
        }

        self.highmgdl = highAlarm
    }

    public func getHighAlarm(forUnit unit: HKUnit) -> Double {

        if unit == HKUnit.millimolesPerLiter {
            return (highmgdl / 18).roundTo(places: 1)
        }
        return highmgdl

    }

}

class AlarmSettingsState: ObservableObject {
    @Published var schedules: [AlarmScheduleState] = []

    static private func setDateComponentState(_ state: AlarmScheduleState) {
        if state.alarmDateComponents.startComponents == nil {
            state.alarmDateComponents.startComponents = DateComponents(hour: 0, minute: 0)
        }

        if state.alarmDateComponents.endComponents == nil {
            state.alarmDateComponents.endComponents = DateComponents(hour: 0, minute: 0)
        }

        let from = state.alarmDateComponents.startComponents!.ToTimeString()
        let to = state.alarmDateComponents.endComponents!.ToTimeString()

        state.alarmDateComponents.componentsAsText = "\(from) - \(to)"

    }

    // this is just to be able to use old serialized schedules from uikit version
    // i.e. we want to be drop in compatible
    static func loadState() -> AlarmSettingsState {

        guard let storedState = UserDefaults.standard.glucoseSchedules, storedState.schedules.count > 0 else {
            print("stored state for alarms was empty")
            let newState = AlarmSettingsState()
            for _ in (0..<GlucoseScheduleList.minimumSchedulesCount) {
                let schedule = AlarmScheduleState()
                setDateComponentState(schedule)
                schedule.enabled = false
                newState.schedules.append(schedule)
            }

            return newState
        }

        let alarmState = AlarmSettingsState()

        print("stored state for alarms contains \(storedState.schedules.count) elements")

        for i in (0..<storedState.schedules.count) {
            let schedule = AlarmScheduleState()

            schedule.enabled = storedState.schedules[i].enabled
            schedule.lowmgdl = storedState.schedules[i].lowAlarm ?? -1
            schedule.highmgdl = storedState.schedules[i].highAlarm ?? -1

            schedule.alarmDateComponents.startComponents = storedState.schedules[i].from
            schedule.alarmDateComponents.endComponents  = storedState.schedules[i].to

            setDateComponentState(schedule)

            alarmState.schedules.append(schedule)

        }

        return alarmState

    }

    func trySaveState() -> StatusMessage? {
        let legacyState = GlucoseScheduleList()
        for newStateSchedule in self.schedules {
            let glucoseSchedule = GlucoseSchedule()
            glucoseSchedule.enabled = newStateSchedule.enabled
            // view is using wrapper binding to store these values so should be safe
            glucoseSchedule.lowAlarm = newStateSchedule.lowmgdl
            glucoseSchedule.highAlarm = newStateSchedule.highmgdl
            glucoseSchedule.from = newStateSchedule.alarmDateComponents.startComponents
            glucoseSchedule.to = newStateSchedule.alarmDateComponents.endComponents

            legacyState.schedules.append(glucoseSchedule)

        }
        let result = legacyState.validateGlucoseSchedules()
        switch result {
        case .success:

            print("glucose schedule valid: \(String(describing: legacyState))")
            UserDefaults.standard.glucoseSchedules = legacyState
        case .error(let description):
            print("Could not save glucose schedules, validation failed: \(description)")
            return StatusMessage(title: "Error", message: description)
        }

        return nil

    }
}

struct AlarmDateRow: View {
    @ObservedObject var schedule: AlarmScheduleState
    @State var tag: Int
    @Binding var subviewSelection: Int?

    var body: some View {

        HStack(alignment: .center) {
            NavigationLink(destination: CustomDataPickerView().environmentObject(schedule.alarmDateComponents),
                           tag: tag,
                           selection: $subviewSelection) {
                Group {
                    systemImage("clock.arrow.2.circlepath")
                        .frame(maxWidth: 50, alignment: .leading)
                    TextField("Active from - to ", text: Binding<String>(get: { "\(schedule.alarmDateComponents.componentsAsText)" },
                                                      set: { schedule.alarmDateComponents.componentsAsText = $0 }))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disableAutocorrection(true)
                        .keyboardType(.decimalPad)
                        .border(Color(UIColor.separator))
                        .disabled(true)
                        .frame(minWidth: 130, idealWidth: 130, maxWidth: .infinity, alignment: .center)
                }.onTapGesture {
                    print("cheduleActivationRow tapped")
                    subviewSelection = tag
                    self.hideKeyboardPreIos16()

                }

            }

            Toggle("", isOn: Binding<Bool>(
                get: {
                    schedule.enabled == true
                },
                set: {
                    if $0 != schedule.enabled {
                        schedule.enabled = $0
                    }
                }
            ))
            .frame(maxWidth: 50, alignment: .trailing)

        }
    }
}

struct AlarmLowRow: View {
    @ObservedObject var schedule: AlarmScheduleState
    var glucoseUnit: HKUnit
    var glucoseUnitDesc: String

    var errorReporter: FormErrorState
    
    @FocusState private var isInputFocused: Bool
    var body: some View {
        HStack(alignment: .center) {

            systemImage("arrowtriangle.down.circle")
                .frame(maxWidth: 50, alignment: .leading)
            Text(LocalizedString("Low", comment: "Text describing Low glucose label in alarmsettingsview"))
                .frame(maxWidth: 100, alignment: .leading)
                .onTapGesture {
                    isInputFocused.toggle()
                }
            Spacer()

            NumericTextField(description: "glucose", showDescription: false,
                             numericValue: Binding<Double>(
                                get: {
                                    schedule.getLowAlarm(forUnit: glucoseUnit)
                                    
                                },
                                set: {
                                    schedule.setLowAlarm(forUnit: glucoseUnit, lowAlarm: $0)
                                }), formErrorState: errorReporter)
            .focused($isInputFocused)

            Text("\(glucoseUnitDesc)")
                .font(.footnote)
                .frame(maxWidth: 100, alignment: .trailing)

        }
        .onTapGesture {
            self.hideKeyboardPreIos16()
        }
    }
}

struct AlarmHighRow: View {
    @ObservedObject var schedule: AlarmScheduleState
    var glucoseUnit: HKUnit
    var glucoseUnitDesc: String

    var errorReporter: FormErrorState
    @FocusState private var isInputFocused: Bool
    var body: some View {
        HStack(alignment: .center) {

            systemImage( "arrowtriangle.up.circle")
                .frame(maxWidth: 50, alignment: .leading)
            Text(LocalizedString("High", comment: "Text describing High glucose label in alarmsettingsview"))
                .frame(maxWidth: 100, alignment: .leading)
                .onTapGesture {
                    isInputFocused.toggle()
                }
            Spacer()

            NumericTextField(description: "glucose", showDescription: false,
                             numericValue: Binding<Double>(
                                get: { schedule.getHighAlarm(forUnit: glucoseUnit) },
                                set: {
                                    schedule.setHighAlarm(forUnit: glucoseUnit, highAlarm: $0)

                                }), formErrorState: errorReporter)
            .focused($isInputFocused)
            Text("\(glucoseUnitDesc)")
                .font(.footnote)
                .frame(maxWidth: 100, alignment: .trailing)

        }
        .onTapGesture {
            self.hideKeyboardPreIos16()
        }
    }
}

struct AlarmSettingsView: View {

    private(set) var glucoseUnit: HKUnit

    var glucoseUnitDesc: String {
        // "mmol/L"
        glucoseUnit.localizedShortUnitString
    }

    @State private var presentableStatus: StatusMessage?
    @StateObject var alarmState = AlarmSettingsState.loadState()
    @State private var subviewSelection: Int?
    
    @State private var authSuccess = false
    
    // Set this to true to require system authentication
    // for accessing the alarm section
    @State private var requiresAuthentication = Features.alarmSettingsViewRequiresAuthentication

    var body: some View {
        erasedWithKeyboardDismissal(list)
        .alert(item: $presentableStatus) { status in
            Alert(title: Text(status.title), message: Text(status.message), dismissButton: .default(Text("Got it!")))
        }
        .navigationBarTitle("Alarm Settings")
        .onAppear {
            if requiresAuthentication && !authSuccess {
                self.authenticate { success in
                    print("got authentication response: \(success)")
                    authSuccess = success
                }
            }
            
        }
        .disabled(requiresAuthentication ? !authSuccess : false)
    }
    
    func erasedWithKeyboardDismissal(_ view: any View) -> AnyView {
        if #available(iOS 16.0, *) {
            return AnyView(view.scrollDismissesKeyboard(.immediately))
        }
        
        return AnyView(view)
    }

    @StateObject var errorReporter = FormErrorState()

    var list: some View {

        List {
            ForEach(Array(alarmState.schedules.enumerated()), id: \.1) { i, schedule in
                Section(header: Text(LocalizedString("Schedule ", comment: "Text describing schedule in alarmsettingsview") +  "\(i+1)")) {
                    AlarmDateRow(schedule: schedule, tag: i, subviewSelection: $subviewSelection)
                    AlarmLowRow(schedule: schedule, glucoseUnit: glucoseUnit, glucoseUnitDesc: glucoseUnitDesc, errorReporter: errorReporter)
                    AlarmHighRow(schedule: schedule, glucoseUnit: glucoseUnit, glucoseUnitDesc: glucoseUnitDesc, errorReporter: errorReporter)

                }.onTapGesture {
                    self.hideKeyboardPreIos16()
                }

            }

            Section {
                Button("Save") {
                    saveButtonAction()
                }.buttonStyle(BlueButtonStyle())
            }
        }
        .listStyle(InsetGroupedListStyle())

    }

    func saveButtonAction() {
        print("tapped save schedules")
        if errorReporter.hasAnyError {
            presentableStatus = StatusMessage(title: "Error", message: "Some ui element was incorrectly specified")
            return
        }
        if let error = alarmState.trySaveState() {
            presentableStatus = error
        } else {
            presentableStatus = StatusMessage(title: "Success", message: "Schedules were saved successfully!")
        }

    }

}

struct AlarmSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AlarmSettingsView(glucoseUnit: .millimolesPerLiter)
    }
}
