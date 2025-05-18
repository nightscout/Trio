//
//  PumpManagerDetailsView.swift
//  OmniBLE
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
        let examplePumpManagerDetails: String = "## OmniBLEPumpManager\nprovideHeartbeat: false\nconnected: true\n\npodComms: ## PodComms\n* myId: 171637F8\n* podId: 171637FB\ndelegate: true\n\nstatusObservers.count: 2\nstatus: ## PumpManagerStatus\n* timeZone: GMT-0700 (fixed)\n* device: <<HKDevice: 0x282f25130>, name:Omnipod-Dash, manufacturer:Insulet, model:Dash, hardware:4, firmware:4.10.0 1.4.0, software:1.0, localIdentifier:171637FB>\n* pumpBatteryChargeRemaining: nil\n* basalDeliveryState: Optional(LoopKit.PumpManagerStatus.BasalDeliveryState.tempBasal(LoopKit.DoseEntry(type: LoopKit.DoseType.tempBasal, startDate: 2023-10-08 00:21:42 +0000, endDate: 2023-10-08 00:51:42 +0000, value: 1.55, unit: LoopKit.DoseUnit.unitsPerHour, deliveredUnits: nil, description: nil, insulinType: Optional(LoopKit.InsulinType.humalog), automatic: Optional(true), manuallyEntered: false, syncIdentifier: nil, isMutable: true, wasProgrammedByPumpUI: false, scheduledBasalRate: nil)))\n* bolusState: noBolus\n* insulinType: Optional(LoopKit.InsulinType.humalog)\n* deliveryIsUncertain: false\n\npodStateObservers.count: 1\nstate: ## OmniBLEPumpManagerState\n* isOnboarded: true\n* timeZone: GMT-0700 (fixed)\n* basalSchedule: BasalSchedule(entries: [OmniBLE.BasalScheduleEntry(rate: 1.0, startTime: 0.0)])\n* maximumTempBasalRate: 5.0\n* unstoredDoses: []\n* suspendEngageState: stable\n* bolusEngageState: stable\n* tempBasalEngageState: stable\n* lastPumpDataReportDate: Optional(2023-09-28 14:03:50 +0000)\n* isPumpDataStale: false\n* silencePod: true\n* confirmationBeeps: extended\n* controllerId: 171637F8\n* podId: 171637FB\n* insulinType: Optional(LoopKit.InsulinType.humalog)\n* scheduledExpirationReminderOffset: Optional(22h0m)\n* defaultExpirationReminderOffset: 24h0m\n* lowReservoirReminderValue: 50.0\n* podAttachmentConfirmed: true\n* activeAlerts: []\n* alertsWithPendingAcknowledgment: []\n* acknowledgedTimeOffsetAlert: false\n* initialConfigurationCompleted: true\n* podState: ### PodState\n* address: 171637FB\n* bleIdentifier: 20672963-16E5-D8F8-9C06-1233FEAA61EB\n* activatedAt: Optional(2023-09-25 06:04:36 +0000)\n* expiresAt: Optional(2023-09-28 06:02:46 +0000)\n* timeActive: 79h59m\n* timeActiveUpdated: Optional(2023-09-28 14:03:50 +0000)\n* setupUnitsDelivered: Optional(2.8)\n* firmwareVersion: 4.10.0\n* bleFirmwareVersion: 1.4.0\n* lotNo: 139865265\n* lotSeq: 2770428\n* suspendState: suspended(2023-09-28 14:02:47 +0000)\n* unacknowledgedCommand: nil\n* unfinalizedBolus: nil\n* unfinalizedTempBasal: nil\n* unfinalizedSuspend: Optional(Suspend: 9/28/23, 7:02:47 AM Certain)\n* unfinalizedResume: Optional(Resume: 9/24/23, 11:06:33 PM Certain)\n* finalizedDoses: []\n* activeAlertsSlots: No alerts\n* messageTransportState: ##\nMessageTransportState\neapSeq: 1059\nmsgSeq: 7\nnonceSeq: 6\nmessageNumber: 14\n* setupProgress: completed\n* primeFinishTime: Optional(2023-10-05 05:46:46 +0000)\n* configuredAlerts: [OmniBLE.AlertSlot.slot7Expired: Pod expired, OmniBLE.AlertSlot.slot2ShutdownImminent: Shutdown imminent, OmniBLE.AlertSlot.slot3ExpirationReminder: Expiration reminder, OmniBLE.AlertSlot.slot4LowReservoir: Low reservoir]\n* insulinType: humalog\n* PdmRef: nil\n* Fault: nil\n\nPreviousPodState: nil"
        NavigationView {
            PumpManagerDetailsView() { completion in
                completion(examplePumpManagerDetails)
            }
        }
    }
}
