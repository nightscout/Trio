//
//  CalibrationEditView.swift
//  LibreTransmitterUI
//
//  Created by LoopKit Authors on 24/03/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import Combine
import LibreTransmitter
import LoopKit

struct NotificationView: View {
    var text: String
    var body: some View {
        HStack(alignment: .center) {
            Text(Image(systemName: "exclamationmark.triangle").resizable())

            +
            Text(text)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                
        }
        .foregroundColor(.black)
        .padding()
        .background(Color.yellow.opacity(0.65))
        .cornerRadius(12)
    }
}

struct CalibrationEditView: View {
    typealias Params = SensorData.CalibrationInfo

    @State private var isPressed = false

    @State private var presentableStatus: StatusMessage?

    public var isReadOnly: Bool {
        if debugMode {
            return false
        }

        return !hasExistingParams
    }

    @ObservedObject fileprivate var formstate = FormErrorState.shared

    var saveButtonSection: some View {
        Section {
            Button(action: {
                print("calibrationsaving in progress")

                self.isPressed.toggle()

                if formstate.hasAnyError {
                    presentableStatus = StatusMessage(title: "Could not save", message: "Some of the fields was not correctly entered")
                    return
                }

                if isReadOnly {
                    presentableStatus = StatusMessage(title: "Could not save", message: "Calibration parameters are readonly and cannot be saved")
                    return
                }

                do {
                    try KeychainManager.standard.setLibreNativeCalibrationData(newParams)
                    print("calibrationsaving completed")

                    presentableStatus = StatusMessage(title: "OK", message: "Calibrations saved!")
                } catch {
                    print("error: \(error.localizedDescription)")
                    presentableStatus = StatusMessage(title: "Calibration error", message: "Calibrations could not be saved, Check that footer crc is non-zero and that all values have sane defaults")
                }

            }, label: {
                Text(LocalizedString("Save", comment: "Text describing Save button in calibrationeditview"))

            }).buttonStyle(BlueButtonStyle())
            .alert(item: $presentableStatus) { status in
                Alert(title: Text(status.title), message: Text(status.message), dismissButton: .default(Text("Got it!")))
            }

        }
    }

    var calibrationInputsSections : some View {
        Group {
            Section {
                NumericTextField(description: "i1", showDescription: true, numericValue: $newParams.i1, isReadOnly: isReadOnly)
                NumericTextField(description: "i2", showDescription: true, numericValue: $newParams.i2, isReadOnly: isReadOnly)
                NumericTextField(description: "i3", showDescription: true, numericValue: $newParams.i3, isReadOnly: isReadOnly)
                NumericTextField(description: "i4", showDescription: true, numericValue: $newParams.i4, isReadOnly: isReadOnly)
                NumericTextField(description: "i5", showDescription: true, numericValue: $newParams.i5, isReadOnly: isReadOnly)
                NumericTextField(description: "i6", showDescription: true, numericValue: $newParams.i6, isReadOnly: isReadOnly)
                
            }
            
            Section{
                NumericTextField(description: "extraSlope", showDescription: true, numericValue: $newParams.extraSlope, isReadOnly: isReadOnly)
                NumericTextField(description: "extraOffset", showDescription: true, numericValue: $newParams.extraOffset, isReadOnly: isReadOnly)
            }
            
        }.disabled(!Features.allowsEditingFactoryCalibrationData)
        
    }

    var validForSection : some View {
        Section {
            Text(LocalizedString("Valid for footer: " , comment: "Text describing technical details about the validity of calibrations ") +  "\(newParams.isValidForFooterWithReverseCRCs)")

        }
    }
    
    

    var body: some View {
        if !Features.allowsEditingFactoryCalibrationData {
            NotificationView(text: "To modify these settings you need to modify the code to allow it")
        }
        List {
            calibrationInputsSections
            validForSection
            if Features.allowsEditingFactoryCalibrationData {
                saveButtonSection
            }
            
        }
        .listStyle(InsetGroupedListStyle())
        .navigationBarTitle(Features.allowsEditingFactoryCalibrationData ? "Calibration Edit" : "Calibration Details")
    }

    @ObservedObject private var newParams: Params

    private var debugMode = false
    private var hasExistingParams = false

    public init(debugMode: Bool=false) {
        self.debugMode = debugMode

        
        if let params = KeychainManager.standard.getLibreNativeCalibrationData() {
            hasExistingParams = true
            self.newParams = params
        } else {
            hasExistingParams = false
            self.newParams = Params(i1: 1, i2: 2, i3: 3, i4: 4, i5: 5, i6: 5, isValidForFooterWithReverseCRCs: 1337)
        }

    }

}

struct CalibrationEditView_Previews: PreviewProvider {
    static var previews: some View {
        // var testData = FormState.shared
        // testData.childStates["i1"] = true
        CalibrationEditView(debugMode: true)

    }
}
