//
//  LowReservoirReminderSetupView.swift
//  OmniKit
//
//  Created by Pete Schwamb on 5/17/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI
import LoopKit
import HealthKit
import OmniKit

struct LowReservoirReminderSetupView: View {

    @State var lowReservoirReminderValue: Int
    
    public var valueChanged: ((_ value: Int) -> Void)?
    public var continueButtonTapped: (() -> Void)?
    public var cancelButtonTapped: (() -> Void)?

    var insulinQuantityFormatter = QuantityFormatter(for: .internationalUnit())

    func formatValue(_ value: Int) -> String {
        return insulinQuantityFormatter.string(from: HKQuantity(unit: .internationalUnit(), doubleValue: Double(value)), for: .internationalUnit()) ?? ""
    }

    var body: some View {
        GuidePage(content: {
            VStack(alignment: .leading, spacing: 15) {
                Text(LocalizedString("The App notifies you when the amount of insulin in the Pod reaches this level (50-10 U).\n\nScroll to set the number of units at which you would like to be reminded.", comment: "Description text on LowReservoirReminderSetupView"))
                Divider()
                HStack {
                    Text(LocalizedString("Low Reservoir", comment: "Label text for low reservoir value row"))
                    Spacer()
                    Text(formatValue(lowReservoirReminderValue))
                }
                picker
            }
            .padding(.vertical, 8)
        }) {
            VStack {
                Button(action: {
                    continueButtonTapped?()
                }) {
                    Text(LocalizedString("Next", comment: "Text of continue button on ExpirationReminderSetupView"))
                        .actionButtonStyle(.primary)
                }
            }
            .padding()
        }
        .navigationBarTitle(LocalizedString("Low Reservoir", comment: "navigation bar title for low reservoir"), displayMode: .automatic)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(LocalizedString("Cancel", comment: "Cancel button title"), action: {
                    cancelButtonTapped?()
                })
            }
        }
    }
    
    private var picker: some View {
        Picker("", selection: $lowReservoirReminderValue) {
            ForEach(Pod.allowedLowReservoirReminderValues, id: \.self) { value in
                Text(formatValue(value))
            }
        }.pickerStyle(WheelPickerStyle())
        .onChange(of: lowReservoirReminderValue) { value in
            valueChanged?(value)
        }

    }

}
struct LowReservoirReminderSetupView_Previews: PreviewProvider {
    static var previews: some View {
        LowReservoirReminderSetupView(lowReservoirReminderValue: 10)
    }
}
