//
//  DeliveryUncertaintyRecoveryView.swift
//  OmniKit
//
//  Created by Pete Schwamb on 8/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI
import RileyLinkBLEKit

struct DeliveryUncertaintyRecoveryView: View {
    
    let model: DeliveryUncertaintyRecoveryViewModel

    @ObservedObject var rileyLinkListDataSource: RileyLinkListDataSource

    var handleRileyLinkSelection: (RileyLinkDevice) -> Void

    @Environment(\.guidanceColors) var guidanceColors

    var body: some View {
        GuidePage(content: {
            Text(String(format: LocalizedString("%1$@ has been unable to communicate with the pod on your body since %2$@.\n\nDo not Discard the Pod without scrolling to read this entire screen.\n\nCommunication was interrupted at a critical time. Information about active insulin / pod temp basal rate is uncertain.\n\nYou can toggle RileyLink connection (below), toggle phone Bluetooth off and on; power the RileyLink device off and on; or try a different RileyLink. (Wait up to 30 seconds for recovery.)\n\nIf you decide to give up because communication cannot be restored, tap the Discard Pod button, follow the steps and start a new pod.\nMonitor your glucose closely for the next 6 hours, as there may or may not be insulin actively working in your body that %3$@ cannot display.", comment: "Format string for main text of delivery uncertainty recovery page. (1: app name)(2: date of command)(3: app name)"), self.model.appName, self.uncertaintyDateLocalizedString, self.model.appName))
                .padding([.top, .bottom])
            Section(header: HStack {
                FrameworkLocalText("Devices", comment: "Header for devices section of RileyLinkSetupView")
                Spacer()
                ProgressView()
            }) {
                ForEach(rileyLinkListDataSource.devices, id: \.peripheralIdentifier) { device in
                    Toggle(isOn: rileyLinkListDataSource.autoconnectBinding(for: device)) {
                        HStack {
                            Text(device.name ?? "Unknown")
                            Spacer()

                            if rileyLinkListDataSource.autoconnectBinding(for: device).wrappedValue {
                                if device.isConnected {
                                    Text(formatRSSI(rssi:device.rssi)).foregroundColor(.secondary)
                                } else {
                                    Image(systemName: "wifi.exclamationmark")
                                        .imageScale(.large)
                                        .foregroundColor(guidanceColors.warning)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleRileyLinkSelection(device)
                        }
                    }
                }
            }
            .onAppear {
                rileyLinkListDataSource.isScanningEnabled = true
                model.respondToRecovery = true
            }
            .onDisappear {
                rileyLinkListDataSource.isScanningEnabled = false
                model.respondToRecovery = false
            }
        }) {
            VStack {
                Text(LocalizedString("Attemping to re-establish communication", comment: "Description string above progress indicator while attempting to re-establish communication from an unacknowledged command")).padding(.top)
                ProgressIndicatorView(state: .indeterminantProgress)
                Button(action: {
                    self.model.onDismiss?()
                }) {
                    Text(LocalizedString("Keep Waiting", comment: "Button title to return to prior screen"))
                    .actionButtonStyle(.primary)
                    .padding([.horizontal])
                }
                Button(action: {
                    self.model.podDeactivationChosen()
                }) {
                    Text(LocalizedString("Discard Pod", comment: "Button title to discard pod on uncertain program"))
                    .actionButtonStyle(.destructive)
                    .padding()
                }
            }
        }
        .navigationBarTitle(Text(LocalizedString("Unable to Reach Pod", comment: "Title of delivery uncertainty recovery page")), displayMode: .large)
        .navigationBarItems(leading: backButton)
    }
    
    private var uncertaintyDateLocalizedString: String {
        DateFormatter.localizedString(from: model.uncertaintyStartedAt, dateStyle: .none, timeStyle: .short)
    }

    var decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()

        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        return formatter
    }()

    private func formatRSSI(rssi: Int?) -> String {
        if let rssi = rssi, let rssiStr = decimalFormatter.decibleString(from: rssi) {
            return rssiStr
        } else {
            return ""
        }
    }
    
    private var backButton: some View {
        Button(LocalizedString("Back", comment: "Back button text on DeliveryUncertaintyRecoveryView"), action: {
            self.model.onDismiss?()
        })
    }
}
