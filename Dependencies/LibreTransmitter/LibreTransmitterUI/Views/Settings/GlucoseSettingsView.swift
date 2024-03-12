//
//  GlucoseSettingsView.swift
//  LibreTransmitterUI
//
//  Created by LoopKit Authors on 26/05/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import Combine
import LibreTransmitter
import HealthKit

struct GlucoseSettingsView: View {

    @State private var presentableStatus: StatusMessage?

    @AppStorage("com.loopkit.libreSyncToNs") var mmSyncToNS: Bool = true
    @AppStorage("com.loopkit.libreBackfillFromHistory") var mmBackfillFromHistory: Bool = true
    @AppStorage("com.loopkit.libreshouldPersistSensorData") var shouldPersistSensorData: Bool = false

    @State private var authSuccess = false
    
    // Set this to true to require system authentication
    // for accessing the glucose section
    @State private var requiresAuthentication = Features.glucoseSettingsRequireAuthentication
    
    var body: some View {
        List {

            Section(header: Text(LocalizedString("Backfill options", comment: "Text describing header for backfill options in glucosesettingsview"))) {
                Toggle("Backfill from history", isOn: $mmBackfillFromHistory)
            }
            Section(header: Text(LocalizedString("Remote data storage", comment: "Text describing header for remote data storage"))) {
                Toggle("Upload to remote data service", isOn: $mmSyncToNS)

            }
            Section(header: Text(LocalizedString("Debug options", comment: "Text describing header for debug options in glucosesettingsview")), footer: Text(LocalizedString("Adds a lot of data to the Issue Report ", comment: "Text informing user of potentially large reports"))) {
                Toggle("Persist sensordata", isOn: $shouldPersistSensorData)
                    .onChange(of: shouldPersistSensorData) {newValue in
                        if !newValue {
                            UserDefaults.standard.queuedSensorData = nil
                        }
                    }
            }
            
        }
        .onAppear {
            if requiresAuthentication && !authSuccess {
                self.authenticate { success in
                    print("got authentication response: \(success)")
                    authSuccess = success
                }
            }
        }
        .disabled(requiresAuthentication ? !authSuccess : false)
        .listStyle(InsetGroupedListStyle())
        .alert(item: $presentableStatus) { status in
            Alert(title: Text(status.title), message: Text(status.message), dismissButton: .default(Text("Got it!")))
        }
        .navigationBarTitle("Glucose Settings")
        
    }

}

struct GlucoseSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        GlucoseSettingsView()
    }
}
