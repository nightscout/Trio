//
//  CustomDataPickerView.swift
//  LibreTransmitterUI
//
//  Created by LoopKit Authors on 28/04/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI

protocol CustomDataPickerDelegate: AnyObject {
    func pickerDidPickValidRange()

}

class AlarmTimeCellExternalState: ObservableObject, Identifiable, Hashable {

    var id = UUID()

    @Published var start: Int = 0
    @Published var end: Int = 0

    // These will be auto populøated
    // when the start and end properties above change
    @Published var startComponents: DateComponents?
    @Published var endComponents: DateComponents?

    @Published var componentsAsText: String = ""

}

// handle parts of alarmsettingsview's state (=externalstate)
struct CustomDataPickerView: View {
    private var startComponentTimes: [DateComponents]
    private var endComponentTimes: [DateComponents]

    private var startTimes = [String]()
    private var endTimes = [String]()

    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var externalState: AlarmTimeCellExternalState

    @State var externalStateCopy: AlarmTimeCellExternalState = AlarmTimeCellExternalState()

    public weak var delegate: CustomDataPickerDelegate?

    private func popView() {
        self.presentationMode.wrappedValue.dismiss()
    }

    static func defaultTimeArray() -> [DateComponents] {
        var arr  = [DateComponents]()

        for hr in 0...23 {
            for min in 0 ..< 2 {
                var components = DateComponents()
                components.hour = hr
                components.minute = min == 1 ? 30 : 0
                arr.append(components)
            }
        }
        var components = DateComponents()
        components.hour = 0
        components.minute = 0
        arr.append(components)

        return arr
    }

    private func callDelegate() {
        delegate?.pickerDidPickValidRange()
    }

    private func verifyRange() {

        // This can be simplified but decided not to do so
        // because the intention becomes more clear

        var isok: Bool

        if externalState.start == 0 || externalState.end == 0 {
            isok = true
        } else {
            if externalState.start > externalState.end {
                isok = false
            } else if externalState.end < externalState.start {
                isok = false
            } else {
                isok = true
            }
        }

        print("is ok? \(isok)")
        if isok {
            updateTextualState()
            callDelegate()
            popView()

        } else {
            presentableStatus = .init(title: "Interval error", message: "Selected time interval was incorrectly specified")
        }

    }

    var pickers: some View {
      HStack {
        Picker("", selection: $externalState.start,
          content: {
            ForEach(startTimes.indices, id: \.self) { i in
              Text("\(startTimes[i])").tag(i)
            }
          }
        )
        // .border(Color.green)

        .zIndex(10)
        .frame(width: 100)
        .clipped()
        .labelsHidden()

        Text(LocalizedString("To ", comment: "Very short text describing separation between start and end datetimes"))

        Picker("", selection: $externalState.end,
          content: {
            ForEach(endTimes.indices, id: \.self) { i in
              Text("\(endTimes[i])").tag(i)
            }
          }
        )
        // .border(Color.red)
        .zIndex(11)
        .frame(width: 100)
        .clipped()
        .labelsHidden()

        // }

        .navigationBarBackButtonHidden(true)
        .navigationBarItems(
          leading:
            Button("Cancel") {
              print("cancel button pressed, restoring state...")
              restoreAlarmExternalState()
              popView()

            }.accentColor(.red),
          trailing:
            Button("Save") {
              print("Save button pressed...")
              verifyRange()
            }
            .disabled(saveButtonDisabled)
            .accentColor(.red)

        )
      }

    }

    @State private var presentableStatus: StatusMessage?
    @State private var saveButtonDisabled = true

    private func updateTextualState(_ shouldDelete: Bool = false) {
        if shouldDelete {
            externalState.componentsAsText = ""
            return
        }
        if let p1 = externalState.startComponents?.ToTimeString(), let p2 = externalState.endComponents?.ToTimeString() {
            externalState.componentsAsText = "\(p1) - \(p2)"
        }
    }

    var body: some View {

        pickers
        .pickerStyle(InlinePickerStyle())
        .onChange(of: externalState.start, perform: { value in
            print("selectedtart changed to \(value)")
            externalState.startComponents = startComponentTimes[value]
            saveButtonDisabled = false

        })
        .onChange(of: externalState.end, perform: { value in
            print("selectedEnd changed to \(value)")
            externalState.endComponents = endComponentTimes[value]
            saveButtonDisabled = false

        })
        .onAppear {
            // this could potentially fail with out of bounds but we trust our parent view!
            externalState.startComponents = startComponentTimes[externalState.start]
            externalState.endComponents = endComponentTimes[externalState.end]
            updateTextualState()

            copyAlarmExternalState()

        }
        .alert(item: $presentableStatus) { status in
            Alert(title: Text(status.title), message: Text(status.message), dismissButton: .default(Text("Got it!")))
        }

    }

    // decided against uding nscoding with copy() here
    private func copyAlarmExternalState() {
        externalStateCopy = AlarmTimeCellExternalState()
        /*
         var id = UUID()

         @Published var start : Int = 0
         @Published var end : Int = 0

         // These will be auto populøated
         // when the start and end properties above change
         @Published var startComponents : DateComponents? = nil
         @Published var endComponents : DateComponents? = nil

         @Published var componentsAsText : String = ""**/
        externalStateCopy.id = externalState.id
        externalStateCopy.start = externalState.start
        externalStateCopy.end = externalState.end
        externalStateCopy.startComponents = externalState.startComponents
        externalStateCopy.endComponents = externalStateCopy.endComponents
        externalStateCopy.componentsAsText = externalState.componentsAsText

    }

    private func restoreAlarmExternalState() {
        externalState.id = externalStateCopy.id
        externalState.start = externalStateCopy.start
        externalState.end = externalStateCopy.end
        externalState.startComponents = externalStateCopy.startComponents
        externalStateCopy.endComponents =  externalStateCopy.endComponents
        externalState.componentsAsText = externalStateCopy.componentsAsText

    }

    init() {
        startComponentTimes = Self.defaultTimeArray()
        endComponentTimes = Self.defaultTimeArray()

        // string representations of the datecomponents arrays   

        for component in startComponentTimes {
            startTimes.append(component.ToTimeString(wantsAMPM: Date.LocaleWantsAMPM))
        }

        for component in endComponentTimes {
            endTimes.append(component.ToTimeString(wantsAMPM: Date.LocaleWantsAMPM))

        }

    }
}

struct CustomDataPickerView_Previews: PreviewProvider {
    static var previews: some View {
        CustomDataPickerView().environmentObject(AlarmTimeCellExternalState())
    }
}
