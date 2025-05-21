//
//  PumpManagerDetailsView.swift
//  OmniKit
//
//  Created by Joe Moran on 9/26/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit


struct PumpManagerDetailsView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    var toRun: ((_ completion: @escaping (_ result: String) -> Void) -> Void)?

    private let title = LocalizedString("Pump Manager Details", comment: "navigation title for pump manager details")
    private let actionString = LocalizedString("Retrieving Pump Manager Details...", comment: "button title when retrieving pump manager details")
    private let buttonTitle = LocalizedString("Refresh Pump Manager Details", comment: "button title to refresh pump manager details")

    @State private var displayString: String = ""
    @State private var error: Error? = nil
    @State private var executing: Bool = false
    @State private var showActivityView: Bool = false

    init(toRun: @escaping (_ completion: @escaping (_ result: String) -> Void) -> Void) {
        self.toRun = toRun
    }

    var body: some View {
        VStack {
            List {
                Section {
                    let myFont = Font
                        .system(size: 12)
                        .monospaced()
                    Text(self.displayString)
                        .font(myFont)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        self.showActivityView = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }.sheet(isPresented: $showActivityView) {
                ActivityView(isPresented: $showActivityView, activityItems: [self.displayString])
            }
            VStack {
                Button(action: {
                    asyncAction()
                }) {
                    Text(buttonText)
                        .actionButtonStyle(.primary)
                }
                .padding()
                .disabled(executing)
            }
            .padding(self.horizontalSizeClass == .regular ? .bottom : [])
            .background(Color(UIColor.secondarySystemGroupedBackground).shadow(radius: 5))
        }
        .insetGroupedListStyle()
        .navigationTitle(title)
         .navigationBarTitleDisplayMode(.automatic)
        .onFirstAppear {
            asyncAction()
        }
    }

    private func asyncAction () {
        DispatchQueue.global(qos: .utility).async {
            executing = true
            self.displayString = ""
            toRun?() { (result) in
                self.displayString = result
                executing = false
            }
        }
    }

    private var buttonText: String {
        if executing {
            return actionString
        } else {
            return buttonTitle
        }
    }
}

struct PumpManagerDetailsView_Previews: PreviewProvider {
    static var previews: some View {
        let examplePumpManagerDetails: String = "## OmnipodPumpManager\n\n## RileyLinkPumpManager\nlastTimerTick: 2023-10-07 22:35:39 +0000\n\n## RileyLinkDeviceManager\n\ncentral: <CBCentralManager: 0x283d877a0>\n\nautoConnectIDs: [\"F0178BCA-967D-504A-8C3A-99E84964B459\"]\n\ntimerTickEnabled: true\n\nidleListeningState: disabled\n\n## RileyLinkDevice\n* name: JPM OrangePro\n* lastIdle: 0001-01-01 00:00:00 +0000\n* isIdleListeningPending: false\n* isTimerTickEnabled: true\n* isTimerTickNotifying: true\n* radioFirmware: Optional(subg_rfspy 2.2)\n* bleFirmware: Optional(ble_rfspy 2.0)\n* peripheralManager: <RileyLinkBLEKit.PeripheralManager: 0x28272cee0>\n* sessionQueue.operationCount: 2\n\npodComms: ## PodComms\nconfiguredDevices: [\"F0178BCA-967D-504A-8C3A-99E84964B459\"]\ndelegate: true\n\nstatusObservers.count: 2\nstatus: ## PumpManagerStatus\n* timeZone: GMT-0700 (fixed)\n* device: <<HKDevice: 0x282cd6120>, name:Omnipod, manufacturer:Insulet, model:Eros, firmware:2.10.0, software:1.0, localIdentifier:1F05DD9A>\n* pumpBatteryChargeRemaining: nil\n* basalDeliveryState: Optional(LoopKit.PumpManagerStatus.BasalDeliveryState.active(2023-10-07 22:33:48 +0000))\n* bolusState: noBolus\n* insulinType: Optional(LoopKit.InsulinType.humalog)\n* deliveryIsUncertain: false\n\npodStateObservers.count: 1\nstate: ## OmnipodPumpManagerState\n* isOnboarded: true\n* timeZone: GMT-0700 (fixed)\n* basalSchedule: BasalSchedule(entries: [OmniKit.BasalScheduleEntry(rate: 0.9, startTime: 0.0)])\n* maximumTempBasalRate: 2.0\n* scheduledExpirationReminderOffset: Optional(\"24h0m\")\n* defaultExpirationReminderOffset: 24h0m\n* lowReservoirReminderValue: 50.0\n* podAttachmentConfirmed: true\n* activeAlerts: []\n* alertsWithPendingAcknowledgment: []\n* acknowledgedTimeOffsetAlert: false\n* initialConfigurationCompleted: true\n* unstoredDoses: []\n* suspendEngageState: stable\n* bolusEngageState: stable\n* tempBasalEngageState: stable\n* lastPumpDataReportDate: Optional(2023-10-07 22:35:24 +0000)\n* isPumpDataStale: false\n* silencePod: false\n* confirmationBeeps: manualCommands\n* pairingAttemptAddress: nil\n* insulinType: Optional(LoopKit.InsulinType.humalog)\n* scheduledExpirationReminderOffset: Optional(\"24h0m\")\n* defaultExpirationReminderOffset: 24h0m\n* rileyLinkBatteryAlertLevel: nil\n* lastRileyLinkBatteryAlertDate 0001-01-01 00:00:00 +0000\n* RileyLinkConnectionManagerState: RileyLinkConnectionState(autoConnectIDs: Set([\"F0178BCA-967D-504A-8C3A-99E84964B459\"]))\n* PodState: ### PodState\n* address: 1F05DD9A\n* activatedAt: Optional(2023-10-07 22:31:21 +0000)\n* expiresAt: Optional(2023-10-10 22:30:51 +0000)\n* timeActive: 4m\n* timeActiveUpdated: Optional(2023-10-07 22:35:38 +0000)\n* setupUnitsDelivered: Optional(2.65)\n* piVersion: 2.10.0\n* pmVersion: 2.10.0\n* lot: 72353\n* tid: 3280440\n* suspendState: resumed(2023-10-07 22:33:48 +0000)\n* unacknowledgedCommand: nil\n* unfinalizedBolus: nil\n* unfinalizedTempBasal: nil\n* unfinalizedSuspend: nil\n* unfinalizedResume: Optional(Resume: 10/7/23, 3:33:48 PM Certain)\n* finalizedDoses: []\n* activeAlertsSlots: No alerts\n* messageTransportState: MessageTransportState(packetNumber: 2, messageNumber: 8)\n* setupProgress: completed\n* primeFinishTime: Optional(2023-10-07 22:33:16 +0000)\n* configuredAlerts: [OmniKit.AlertSlot.slot4LowReservoir: Low reservoir, OmniKit.AlertSlot.slot3ExpirationReminder: Expiration reminder, OmniKit.AlertSlot.slot2ShutdownImminent: Shutdown imminent, OmniKit.AlertSlot.slot7Expired: Pod expired]\n* insulinType: humalog\n* PdmRef: nil\n* Fault: nil\n\n* PreviousPodState: nil\n"
        NavigationView {
            PumpManagerDetailsView() { completion in
                completion(examplePumpManagerDetails)
            }
        }
    }
}
