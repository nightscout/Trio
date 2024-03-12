//
//  CriticalAlarmsVolumeView.swift
//  LibreTransmitterUI
//
//  Created by LoopKit Authors on 29/01/2023.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct CriticalAlarmsVolumeView: View {

    private var intVolume : Int {
        Int(mmCriticalAlarmsVolume)
    }
    @State private var isEditing = false
    
    private enum Key: String {
        case mmCriticalAlarmsVolume = "com.loopkit.libreCriticalAlarmsVolume"
    }
    
    @AppStorage(Key.mmCriticalAlarmsVolume.rawValue) var mmCriticalAlarmsVolume: Double = 60
    
    var body: some View {
        List {
            Section(header: Text("Critical alarm volume"), footer: Text("Critical alarms will always be sent with volume at minimum 60%")) {
                Slider(
                    value: $mmCriticalAlarmsVolume,
                    in: 60...100,
                    step: 5,
                    onEditingChanged: { editing in
                        isEditing = editing
                    }
                )
                Text("\(intVolume)%")
                    .foregroundColor(isEditing ? .red : .blue)
                
            }
        }
    }
}

struct CriticalAlarmsVolumeView_Previews: PreviewProvider {
    static var previews: some View {
        CriticalAlarmsVolumeView()
    }
}
