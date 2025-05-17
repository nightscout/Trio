//
//  ManualTempBasalEntryView.swift
//  OmniKit
//
//  Created by Pete Schwamb on 5/14/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI
import LoopKit
import HealthKit
import OmniKit

struct ManualTempBasalEntryView: View {

    @Environment(\.guidanceColors) var guidanceColors

    var enactBasal: ((Double,TimeInterval,@escaping (PumpManagerError?)->Void) -> Void)?
    var didCancel: (() -> Void)?

    @State private var rateEntered: Double = 0.0
    @State private var durationEntered: TimeInterval = .hours(0.5)
    @State private var showPicker: Bool = false
    @State private var error: PumpManagerError?
    @State private var enacting: Bool = false
    @State private var showingErrorAlert: Bool = false
    @State private var showingMissingConfigAlert: Bool = false

    var allowedRates: [Double]

    init(enactBasal: ((Double,TimeInterval,@escaping (PumpManagerError?)->Void) -> Void)? = nil, didCancel: (() -> Void)? = nil, allowedRates: [Double]) {
        self.enactBasal = enactBasal
        self.didCancel = didCancel
        self.allowedRates = allowedRates
        // This is to handle users migrating from OmnipodPumpManagerState with no max temp basal set
        if allowedRates.count <= 1 {
            _showingMissingConfigAlert = State(initialValue: true)
        }
    }

    private static let rateFormatter: QuantityFormatter = {
        let quantityFormatter = QuantityFormatter()
        quantityFormatter.setPreferredNumberFormatter(for: .internationalUnitsPerHour)
        quantityFormatter.numberFormatter.minimumFractionDigits = 2
        return quantityFormatter
    }()

    private var rateUnitsLabel: some View {
        Text(QuantityFormatter().string(from: .internationalUnitsPerHour))
            .foregroundColor(Color(.secondaryLabel))
    }

    private static let durationFormatter: QuantityFormatter = {
        let quantityFormatter = QuantityFormatter()
        quantityFormatter.setPreferredNumberFormatter(for: .hour())
        quantityFormatter.numberFormatter.minimumFractionDigits = 1
        quantityFormatter.numberFormatter.maximumFractionDigits = 1
        quantityFormatter.unitStyle = .long
        return quantityFormatter
    }()

    private var durationUnitsLabel: some View {
        Text(QuantityFormatter().string(from: .hour()))
            .foregroundColor(Color(.secondaryLabel))
    }

    func formatRate(_ rate: Double) -> String {
        let unit = HKUnit.internationalUnitsPerHour
        return ManualTempBasalEntryView.rateFormatter.string(from: HKQuantity(unit: unit, doubleValue: rate), for: unit) ?? ""
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let unit = HKUnit.hour()
        return ManualTempBasalEntryView.durationFormatter.string(from: HKQuantity(unit: unit, doubleValue: duration.hours), for: unit) ?? ""
    }

    var body: some View {
        NavigationView {
            VStack {
                List {
                    HStack {
                        Text(LocalizedString("Rate", comment: "Label text for basal rate summary"))
                        Spacer()
                        Text(String(format: LocalizedString("%1$@ for %2$@", comment: "Summary string for temporary basal rate configuration page"), formatRate(rateEntered), formatDuration(durationEntered)))
                    }
                    HStack {
                        ResizeablePicker(selection: $rateEntered,
                                         data: allowedRates,
                                         formatter: { formatRate($0) })
                        ResizeablePicker(selection: $durationEntered,
                                         data: Pod.supportedTempBasalDurations,
                                         formatter: { formatDuration($0) })
                    }
                    .frame(maxHeight: 162.0)
                    .alert(isPresented: $showingMissingConfigAlert, content: { missingConfigAlert })
                    Section {
                        Text(LocalizedString("Your insulin delivery will not be automatically adjusted until the temporary basal rate finishes or is canceled.", comment: "Description text on manual temp basal action sheet"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button(action: {
                    enacting = true
                    enactBasal?(rateEntered, durationEntered) { (error) in
                        if let error = error {
                            self.error = error
                            showingErrorAlert = true
                        }
                        enacting = false
                    }
                }) {
                    HStack {
                        if enacting {
                            ProgressView()
                        } else {
                            Text(LocalizedString("Set Temporary Basal", comment: "Button text for setting manual temporary basal rate"))
                        }
                    }
                }
                .buttonStyle(ActionButtonStyle(.primary))
                .padding()
            }
            .navigationTitle(LocalizedString("Temporary Basal", comment: "Navigation Title for ManualTempBasalEntryView"))
            .navigationBarItems(trailing: cancelButton)
            .alert(isPresented: $showingErrorAlert, content: { errorAlert })
            .disabled(enacting)
        }
    }

    var errorAlert: SwiftUI.Alert {
        let errorMessage = errorMessage(error: error!)
        return SwiftUI.Alert(
            title: Text(LocalizedString("Temporary Basal Failed", comment: "Alert title for a failure to set temporary basal")),
            message: errorMessage)
    }

    func errorMessage(error: PumpManagerError) -> Text {
        if let recovery = error.recoverySuggestion {
            return Text(String(format: LocalizedString("Unable to set a temporary basal rate: %1$@\n\n%2$@", comment: "Alert format string for a failure to set temporary basal with recovery suggestion. (1: error description) (2: recovery text)"), error.localizedDescription, recovery))
        } else {
            return Text(String(format: LocalizedString("Unable to set a temporary basal rate: %1$@", comment: "Alert format string for a failure to set temporary basal. (1: error description)"), error.localizedDescription))
        }
    }

    var missingConfigAlert: SwiftUI.Alert {
        return SwiftUI.Alert(
            title: Text(LocalizedString("Missing Config", comment: "Alert title for missing temp basal configuration")),
            message: Text(LocalizedString("This Pump has not been configured with a maximum basal rate because it was added before manual temp basal was a feature. Please go to Pump Settings in the settings CONFIGURATION section to set a new Max Basal.", comment: "Alert format string for missing temp basal configuration."))
        )
    }


    var cancelButton: some View {
        Button(LocalizedString("Cancel", comment: "Cancel button text in navigation bar on insert cannula screen")) {
            didCancel?()
        }
        .accessibility(identifier: "button_cancel")
    }
}
