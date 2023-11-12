//
//  ExpirationReminderPickerView.swift
//  OmniBLE
//
//  Created by Pete Schwamb on 5/17/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import HealthKit

struct ExpirationReminderPickerView: View {
    
    static let expirationReminderHoursAllowed = 0...24
    
    var expirationReminderDefault: Binding<Int>
    
    var collapsible: Bool = true
    
    @State var showingHourPicker: Bool = false
    
    var expirationDefaultFormatter = QuantityFormatter(for: .hour())
    
    var expirationDefaultString: String {
        return expirationReminderHourString(expirationReminderDefault.wrappedValue)
    }
    
    var body: some View {
        VStack {
            HStack {
                Text(LocalizedString("Expiration Reminder Default", comment: "Label text for expiration reminder default row"))
                Spacer()
                if collapsible {
                    Button(expirationDefaultString) {
                        withAnimation {
                            showingHourPicker.toggle()
                        }
                    }
                } else {
                    Text(expirationDefaultString)
                }
            }
            if showingHourPicker {
                ResizeablePicker(selection: expirationReminderDefault,
                                 data: Array(Self.expirationReminderHoursAllowed),
                                 formatter: { expirationReminderHourString($0) })
            }
        }
    }
    
    private func expirationReminderHourString(_ value: Int) -> String {
        if value > 0 {
            return expirationDefaultFormatter.string(from: HKQuantity(unit: .hour(), doubleValue: Double(value)), for: .hour())!
        } else {
            return LocalizedString("No Reminder", comment: "Value text for no expiration reminder")
        }
    }
}

struct ExpirationReminderPickerView_Previews: PreviewProvider {
    static var previews: some View {
        ExpirationReminderPickerView(expirationReminderDefault: .constant(2), showingHourPicker: true)
    }
}
