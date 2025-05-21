//
//  ReadPodStatusView.swift
//  OmniBLE
//
//  Created by Joe Moran on 8/15/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit


struct ReadPodStatusView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    var toRun: ((_ completion: @escaping (_ result: PumpManagerResult<DetailedStatus>) -> Void) -> Void)?

    private let title = LocalizedString("Read Pod Status", comment: "navigation title for read pod status")
    private let actionString = LocalizedString("Reading Pod Status...", comment: "button title when executing read pod status")
    private let failedString = LocalizedString("Failed to read pod status.", comment: "Alert title for error when reading pod status")

    @State private var alertIsPresented: Bool = false
    @State private var displayString: String = ""
    @State private var error: LocalizedError? = nil
    @State private var executing: Bool = false
    @State private var showActivityView: Bool = false

    var body: some View {
        VStack {
            List {
                Section {
                    Text(self.displayString).fixedSize(horizontal: false, vertical: true)
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
        .alert(isPresented: $alertIsPresented, content: { alert(error: error) })
        .onFirstAppear {
            asyncAction()
        }
    }

    private func asyncAction () {
        DispatchQueue.global(qos: .utility).async {
            executing = true
            self.displayString = ""
            toRun?() { (result) in
                executing = false
                switch result {
                case .success(let detailedStatus):
                    self.displayString = podStatusString(status: detailedStatus)
                case .failure(let error):
                    self.error = error
                    self.alertIsPresented = true
                }
            }
        }
    }

    private var buttonText: String {
        if executing {
            return actionString
        } else {
            return title
        }
    }

    private func alert(error: Error?) -> SwiftUI.Alert {
        return SwiftUI.Alert(
            title: Text(failedString),
            message: Text(error?.localizedDescription ?? "No Error")
        )
    }
}

private func podStatusString(status: DetailedStatus) -> String {
    var result, str: String

    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .full
    formatter.allowedUnits = [.hour, .minute]
    formatter.unitsStyle = .short
    if let timeStr = formatter.string(from: status.timeActive) {
        str = timeStr
    } else {
        str = String(format: LocalizedString("%1$@ minutes", comment: "The format string for minutes (1: number of minutes string)"), String(describing: Int(status.timeActive / 60)))
    }
    result = String(format: LocalizedString("Pod Active: %1$@", comment: "The format string for Pod Active: (1: formatted time)"), str)

    result += String(format: LocalizedString("\nPod Progress: %1$@", comment: "The format string for Pod Progress: (1: pod progress string)"), String(describing: status.podProgressStatus))

    result += String(format: LocalizedString("\nDelivery Status: %1$@", comment: "The format string for Delivery Status: (1: delivery status string)"), String(describing: status.deliveryStatus))

    result += String(format: LocalizedString("\nLast Programming Seq Num: %1$@", comment: "The format string for last programming sequence number: (1: last programming sequence number)"), String(describing: status.lastProgrammingMessageSeqNum))

    result += String(format: LocalizedString("\nBolus Not Delivered: %1$@ U", comment: "The format string for Bolus Not Delivered: (1: bolus not delivered string)"), status.bolusNotDelivered.twoDecimals)

    result += String(format: LocalizedString("\nPulse Count: %1$d", comment: "The format string for Pulse Count (1: pulse count)"), Int(round(status.totalInsulinDelivered / Pod.pulseSize)))

    result += String(format: LocalizedString("\nReservoir Level: %1$@ U", comment: "The format string for Reservoir Level: (1: reservoir level string)"), status.reservoirLevel == Pod.reservoirLevelAboveThresholdMagicNumber ? "50+" : status.reservoirLevel.twoDecimals)

    result += String(format: LocalizedString("\nAlerts: %1$@", comment: "The format string for Alerts: (1: the alerts string)"), alertSetString(alertSet: status.unacknowledgedAlerts))

    if status.radioRSSI != 0 {
        result += String(format: LocalizedString("\nRSSI: %1$@", comment: "The format string for RSSI: (1: RSSI value)"), String(describing: status.radioRSSI))
        result += String(format: LocalizedString("\nReceiver Low Gain: %1$@", comment: "The format string for receiverLowGain: (1: receiverLowGain)"), String(describing: status.receiverLowGain))
    }

    if status.faultEventCode.faultType != .noFaults {
        // report the additional fault related information in a separate section
        result += String(format: LocalizedString("\n\n⚠️ Critical Pod Fault %1$03d (0x%2$02X)", comment: "The format string for fault code in decimal and hex: (1: fault code for decimal display) (2: fault code for hex display)"), status.faultEventCode.rawValue, status.faultEventCode.rawValue)
        result += String(format: "\n%1$@", status.faultEventCode.faultDescription)
        if let faultEventTimeSinceActivation = status.faultEventTimeSinceActivation,
           let faultTimeStr = formatter.string(from: faultEventTimeSinceActivation)
        {
            result += String(format: LocalizedString("\nFault Time: %1$@", comment: "The format string for fault time: (1: fault time string)"), faultTimeStr)
        }
        if let errorEventInfo = status.errorEventInfo {
            result += String(format: LocalizedString("\nFault Event Info: %1$03d (0x%2$02X),", comment: "The format string for fault event info: (1: fault event info)"), errorEventInfo.rawValue, errorEventInfo.rawValue)
            result += String(format: LocalizedString("\n  Insulin State Table Corrupted: %@", comment: "The format string for insulin state table corrupted: (1: insulin state corrupted)"), String(describing: errorEventInfo.insulinStateTableCorruption))
            result += String(format: LocalizedString("\n  Occlusion Type: %1$@", comment: "The format string for occlusion type: (1: occlusion type)"), String(describing: errorEventInfo.occlusionType))
            result += String(format: LocalizedString("\n  Immediate Bolus In Progress: %1$@", comment: "The format string for immediate bolus in progress: (1: immediate bolus in progress)"), String(describing: errorEventInfo.immediateBolusInProgress))
            result += String(format: LocalizedString("\n  Previous Pod Progress: %1$@", comment: "The format string for previous pod progress: (1: previous pod progress string)"), String(describing: errorEventInfo.podProgressStatus))
        }
        if let pdmRef = status.pdmRef {
            result += String(format: LocalizedString("\nRef: %@", comment: "The Ref format string (1: pdm ref string)"), pdmRef)
        }
    }

    return result
}

struct ReadPodStatusView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            let detailedStatus = try! DetailedStatus(encodedData: Data([0x02, 0x0d, 0x00, 0x00, 0x00, 0x0e, 0x00, 0xc3, 0x6a, 0x02, 0x07, 0x03, 0xff, 0x02, 0x09, 0x20, 0x00, 0x28, 0x00, 0x08, 0x00, 0x82]))
            ReadPodStatusView() { completion in
                completion(.success(detailedStatus))
            }
        }
    }
}
