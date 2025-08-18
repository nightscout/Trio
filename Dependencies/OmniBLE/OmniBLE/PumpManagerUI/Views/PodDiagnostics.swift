//
//  PodDiagnotics.swift
//  OmniBLE
//
//  Created by Joseph Moran on 11/25/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import HealthKit


struct PodDiagnosticsView: View  {

    var title: String
    
    @ObservedObject var viewModel: OmniBLESettingsViewModel

    var body: some View {
        List {
            NavigationLink(destination: ReadPodStatusView(toRun: viewModel.readPodStatus)) {
                FrameworkLocalText("Read Pod Status", comment: "Text for read pod status navigation link")
                    .foregroundColor(Color.primary)
            }
            .disabled(self.viewModel.noPod)

            NavigationLink(destination: PlayTestBeepsView(toRun: viewModel.playTestBeeps)) {
                FrameworkLocalText("Play Test Beeps", comment: "Text for play test beeps navigation link")
                    .foregroundColor(Color.primary)
            }
            .disabled(!self.viewModel.podOk)

            NavigationLink(destination: ReadPodInfoView(
                title: LocalizedString("Read Pulse Log", comment: "Text for read pulse log title"),
                actionString: LocalizedString("Reading Pulse Log...", comment: "Text for read pulse log action"),
                failedString: LocalizedString("Failed to read pulse log.", comment: "Alert title for error when reading pulse log"),
                toRun: viewModel.readPulseLog))
            {
                FrameworkLocalText("Read Pulse Log", comment: "Text for read pulse log navigation link")
                    .foregroundColor(Color.primary)
            }
            .disabled(self.viewModel.noPod)

            NavigationLink(destination: ReadPodInfoView(
                title: LocalizedString("Read Pulse Log Plus", comment: "Text for read pulse log plus title"),
                actionString: LocalizedString("Reading Pulse Log Plus...", comment: "Text for read pulse log plus action"),
                failedString: LocalizedString("Failed to read pulse log plus.", comment: "Alert title for error when reading pulse log plus"),
                toRun: viewModel.readPulseLogPlus))
            {
                FrameworkLocalText("Read Pulse Log Plus", comment: "Text for read pulse log plus navigation link")
                    .foregroundColor(Color.primary)
            }
            .disabled(self.viewModel.noPod)

            NavigationLink(destination: ReadPodInfoView(
                title: LocalizedString("Read Activation Time", comment: "Text for read activation time title"),
                actionString: LocalizedString("Reading Activation Time...", comment: "Text for read activation time action"),
                failedString: LocalizedString("Failed to read activation time.", comment: "Alert title for error when reading activation time"),
                toRun: self.viewModel.readActivationTime))
            {
                FrameworkLocalText("Read Activation Time", comment: "Text for read activation time navigation link")
                    .foregroundColor(Color.primary)
            }
            .disabled(self.viewModel.noPod)

            NavigationLink(destination: ReadPodInfoView(
                title: LocalizedString("Read Triggered Alerts", comment: "Text for read triggered alerts title"),
                actionString: LocalizedString("Reading Triggered Alerts...", comment: "Text for read triggered alerts action"),
                failedString: LocalizedString("Failed to read triggered alerts.", comment: "Alert title for error when reading triggered alerts"),
                toRun: self.viewModel.readTriggeredAlerts))
            {
                FrameworkLocalText("Read Triggered Alerts", comment: "Text for read triggered alerts navigation link")
                    .foregroundColor(Color.primary)
            }
            .disabled(self.viewModel.noPod)

            NavigationLink(destination: PumpManagerDetailsView(
                toRun: self.viewModel.pumpManagerDetails))
            {
                FrameworkLocalText("Pump Manager Details", comment: "Text for pump manager details navigation link")
                    .foregroundColor(Color.primary)
            }
        }
        .insetGroupedListStyle()
        .navigationBarTitle(title)
    }
}
