//
//  ModeSelectionView.swift
//  LibreTransmitterUI
//
//  Created by LoopKit Authors on 02/09/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI
import LibreTransmitter

struct ModeSelectionView: View {

    @ObservedObject public var cancelNotifier: GenericObservableObject
    @ObservedObject public var saveNotifier: GenericObservableObject

    var pairingService: SensorPairingProtocol
    var bluetoothSearcher: BluetoothSearcher

    var modeSelectSection : some View {
        Section(header: Text(LocalizedString("Connection options", comment: "Text describing options for connecting to sensor or transmitter"))) {

            NavigationLink(destination: Libre2DirectSetup(cancelNotifier: cancelNotifier, saveNotifier: saveNotifier, pairingService: pairingService)) {
                SettingsItem(title: LocalizedString("Libre 2 Direct", comment: "Libre 2 connection option"))
                    .actionButtonStyle(.primary)
                    .padding([.top, .bottom], 8)
            }

            NavigationLink(destination: BluetoothSelection(cancelNotifier: cancelNotifier, saveNotifier: saveNotifier, searcher: bluetoothSearcher)) {
                SettingsItem(title: LocalizedString("Bluetooth Transmitters", comment: "Bluetooth Transmitter connection option"))
                    .actionButtonStyle(.primary)
                    .padding([.top, .bottom], 8)
            }
        }
    }

    var cancelButton: some View {
        Button(LocalizedString("Cancel", comment: "Cancel button")) {
            cancelNotifier.notify()

        }// .accentColor(.red)
    }

    var body : some View {
        GuidePage(content: {
            VStack {
                getLeadingImage()
                
                HStack {
                    InstructionList(instructions: [
                        LocalizedString("Sensor should be activated and fully warmed up.", comment: "Label text for step 1 of connection setup"),
                        LocalizedString("Select the type of setup you want.", comment: "Label text for step 2 of connection setup"),
                        LocalizedString("Most libre 1 and libre 2 sensors are supported, except North America Libre 2; see readme.md for details.", comment: "Label text for step 3 of connection setup"),
                        LocalizedString("Fair warning: The sensor will be not be using the manufacturer's algorithm, and some safety mitigations present in the manufacturers algorithm might be missing when you use this.", comment: "Label text for step 4 of connection setup")
                    ])
                }
  
            }

        }) {
            VStack(spacing: 10) {
                modeSelectSection
            }.padding()
        }
        
        .navigationBarTitle("New Device Setup", displayMode: .large)
        .navigationBarItems(trailing: cancelButton)
        .navigationBarBackButtonHidden(true)
    }
}

struct ModeSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        ModeSelectionView(cancelNotifier: GenericObservableObject(), saveNotifier: GenericObservableObject(), pairingService: MockSensorPairingService(), bluetoothSearcher: MockBluetoothSearcher())
    }
}
