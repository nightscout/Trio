//
//  AuthView.swift
//  LibreTransmitterUI
//
//  Created by LoopKit Authors on 23/01/2023.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI
import LibreTransmitter

// this view should only be called when setting up a new device in an existing cgmmanager
struct AuthView: View {
    
    // The idea is that the cancel and save notifiers will call this complete notifier from the parent
    @ObservedObject public var completeNotifier : GenericObservableObject
    @ObservedObject public var notifyReset: GenericObservableObject
    @ObservedObject public var notifyReconnect: GenericObservableObject
    
    @StateObject public var cancelNotifier = GenericObservableObject()
    @StateObject public var saveNotifier = GenericObservableObject()
    
    @State private var isAuthenticated = false
    @State private var hasSetupListeners = false

    var pairingService: SensorPairingProtocol
    var bluetoothSearcher: BluetoothSearcher
    
    var exclamation: Image {
        Image(systemName: "exclamationmark.triangle.fill")
            
    }
    
    @State var isNavigationActive = false
 
    var buttonSection : some View {
        Section {
            
            if isAuthenticated {
                ProgressIndicatorView(state: .completed)
                Text(LocalizedString("Authenticated", comment: "Text confirming user is authenticated in AuthView"))
                    
                    .transition(AnyTransition.opacity.combined(with: .move(edge: .bottom)))
                NavigationLink(destination: ModeSelectionView(cancelNotifier: cancelNotifier, saveNotifier: saveNotifier, pairingService: pairingService, bluetoothSearcher: bluetoothSearcher), isActive: $isNavigationActive) {
                    Button(action: {
                        self.notifyReset.notify()
                        self.isNavigationActive = true
                    }) {
                        Text(LocalizedString("Disconnect & Continue Setup", comment: "Text of Sensor Setup Button in AuthView"))
                            .actionButtonStyle(.destructive)
                    }
                    
                }
                .disabled(!isAuthenticated)
            } else {
                Button(action: {
                    self.authenticate { success in
                        self.isAuthenticated = success
                    }
                }) {
                    Text(LocalizedString("Authenticate", comment: "Text of Authenticate button in AuthView"))
                        .actionButtonStyle(.primary)
                }
                
            }
            
        }
        
    }
    
    var cancelButton: some View {
        Button("Cancel") {
            // no need to reconnect here as we haven't been asked to disconnect yet
            completeNotifier.notify()
            
            // If commented out, this will force bluetooth state restoration. Great for testing
            // notifyReconnect.notify()
        }
    }
    
    func handleCancel() {
        // Cancel request is coming in from a subview
        // In all cases this means that the connection to existing sensor has been terminated
        // So we always need to reconnect
        print("\(#function) called on authview")
        // completeNotifier.notify()
        notifyReconnect.notify()
    }
    
    func handleSave() {
        print("\(#function) called on authview")
        // completeNotifier.notify()
        
        let hasNewDevice = SelectionState.shared.selectedStringIdentifier != UserDefaults.standard.preSelectedDevice
        if hasNewDevice, let newDevice = SelectionState.shared.selectedStringIdentifier {
            print("authview will set new device to \(newDevice)")
            UserDefaults.standard.preSelectedDevice = newDevice
            SelectionState.shared.selectedUID = nil
            UserDefaults.standard.preSelectedUid = nil

        } else if let newUID = SelectionState.shared.selectedUID {
            // this one is only temporary,
            // as we don't know the bluetooth identifier during nfc setup
            print("authview will set new libre2 device  to \(newUID.hex)")

            UserDefaults.standard.preSelectedUid = newUID
            SelectionState.shared.selectedUID = nil
            UserDefaults.standard.preSelectedDevice = nil

        } else {

            // this cannot really happen unless you are a developer and have previously
            // stored both preSelectedDevice and selectedUID !
        }
        
        notifyReconnect.notify()
    }
    
    var body: some View {
        
        GuidePage(content: {
            VStack(alignment: .center, spacing: 24) {
                getLeadingImage()
                
                HStack {
                    InstructionList(instructions: [
                        LocalizedString("Activate and finish warming up a new sensor with another app or physical reader.", comment: "Label text for step 1 of AuthView"),
                        LocalizedString("Press the Authenticate Button.", comment: "Label text for step 2 of AuthView"),
                        LocalizedString("Proceed to pair new sensor in the next screens. Note that you will loose connection to any existing sensor or transmitter", comment: "Label text for step 3 of AuthView")
                    ])
                }
                Spacer()
  
            }
            .padding(.vertical, 8)

        }) {
            VStack {
                buttonSection
            }
            .padding()
        }
        
        .navigationBarTitle("New Device Setup")
        .navigationBarItems(trailing: cancelButton)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if !hasSetupListeners {
                hasSetupListeners = true
                
                cancelNotifier.listenOnce(listener: handleCancel)
                saveNotifier.listenOnce(listener: handleSave)
            }
            
        }

    }
}

struct AuthView_Previews: PreviewProvider {
    static var previews: some View {
        AuthView(completeNotifier: GenericObservableObject(), notifyReset: GenericObservableObject(), notifyReconnect: GenericObservableObject(), pairingService: MockSensorPairingService(), bluetoothSearcher: MockBluetoothSearcher())
    }
}
