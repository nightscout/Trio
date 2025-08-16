//
//  G7SettingsView.swift
//  CGMBLEKitUI
//
//  Created by Pete Schwamb on 9/25/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI
import G7SensorKit
import LoopKitUI

struct G7SettingsView: View {

    private var durationFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    @Environment(\.guidanceColors) private var guidanceColors
    @Environment(\.glucoseTintColor) private var glucoseTintColor

    var didFinish: (() -> Void)
    var deleteCGM: (() -> Void)
    @ObservedObject var viewModel: G7SettingsViewModel

    @State private var showingDeletionSheet = false

    init(didFinish: @escaping () -> Void, deleteCGM: @escaping () -> Void, viewModel: G7SettingsViewModel) {
        self.didFinish = didFinish
        self.deleteCGM = deleteCGM
        self.viewModel = viewModel
    }

    private var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()

        formatter.dateStyle = .short
        formatter.timeStyle = .short

        return formatter
    }()

    var body: some View {
        List {
            Section() {
                VStack {
                    headerImage
                    progressBar
                }
            }
            if let activatedAt = viewModel.activatedAt {
                HStack {
                    Text(LocalizedString("Sensor Start", comment: "title for g7 settings row showing sensor start time"))
                    Spacer()
                    Text(timeFormatter.string(from: activatedAt))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text(LocalizedString("Sensor Expiration", comment: "title for g7 settings row showing sensor expiration time"))
                    Spacer()
                    Text(timeFormatter.string(from: activatedAt.addingTimeInterval(G7Sensor.lifetime)))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text(LocalizedString("Grace Period End", comment: "title for g7 settings row showing sensor grace period end time"))
                    Spacer()
                    Text(timeFormatter.string(from: activatedAt.addingTimeInterval(G7Sensor.lifetime + G7Sensor.gracePeriod)))
                        .foregroundColor(.secondary)
                }
            }

            Section(LocalizedString("Last Reading", comment: "")) {
                LabeledValueView(label: LocalizedString("Glucose", comment: "Field label"),
                                 value: viewModel.lastGlucoseString)
                LabeledDateView(label: LocalizedString("Time", comment: "Field label"),
                                date: viewModel.latestReadingTimestamp,
                                dateFormatter: viewModel.dateFormatter)
                LabeledValueView(label: LocalizedString("Trend", comment: "Field label"),
                                 value: viewModel.lastGlucoseTrendString)
            }

            Section(LocalizedString("Bluetooth", comment: "")) {
                if let name = viewModel.sensorName {
                    HStack {
                        Text(LocalizedString("Name", comment: "title for g7 settings row showing BLE Name"))
                        Spacer()
                        Text(name)
                            .foregroundColor(.secondary)
                    }
                }
                if viewModel.scanning {
                    HStack {
                        Text(LocalizedString("Scanning", comment: "title for g7 settings connection status when scanning"))
                        Spacer()
                        SwiftUI.ProgressView()
                    }
                } else {
                    if viewModel.connected {
                        Text(LocalizedString("Connected", comment: "title for g7 settings connection status when connected"))
                    } else {
                        HStack {
                            Text(LocalizedString("Connecting", comment: "title for g7 settings connection status when connecting"))
                            Spacer()
                            SwiftUI.ProgressView()
                        }
                    }
                }
                if let lastConnect = viewModel.lastConnect {
                    LabeledValueView(label: LocalizedString("Last Connect", comment: "title for g7 settings row showing sensor last connect time"),
                                     value: timeFormatter.string(from: lastConnect))
                }
            }

            Section(LocalizedString("Configuration", comment: "")) {
                HStack {
                    Toggle(LocalizedString("Upload Readings", comment: "title for g7 config settings to upload readings"), isOn: $viewModel.uploadReadings)
                }
            }

            Section () {
                if !self.viewModel.scanning {
                    Button(LocalizedString("Scan for new sensor", comment: ""), action: {
                        self.viewModel.scanForNewSensor()
                    })
                }

                deleteCGMButton
            }
        }
        .insetGroupedListStyle()
        .navigationBarItems(trailing: doneButton)
        .navigationBarTitle(LocalizedString("Dexcom G7", comment: "Navigation bar title for G7SettingsView"))
    }

    private var deleteCGMButton: some View {
        Button(action: {
            showingDeletionSheet = true
        }, label: {
            Text(LocalizedString("Delete CGM", comment: "Button label for removing CGM"))
                .foregroundColor(.red)
        }).actionSheet(isPresented: $showingDeletionSheet) {
            ActionSheet(
                title: Text("Are you sure you want to delete this CGM?"),
                buttons: [
                    .destructive(Text("Delete CGM")) {
                        self.deleteCGM()
                    },
                    .cancel(),
                ]
            )
        }
    }

    private var headerImage: some View {
        VStack(alignment: .center) {
            Image(frameworkImage: "g7")
                .resizable()
                .aspectRatio(contentMode: ContentMode.fit)
                .frame(height: 150)
                .padding(.horizontal)
        }.frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.progressBarState.label)
                    .font(.system(size: 17))
                    .foregroundColor(color(for: viewModel.progressBarState.labelColor))

                Spacer()
                if let referenceDate = viewModel.progressReferenceDate {
                    Text(durationFormatter.localizedString(for: referenceDate, relativeTo: Date()))
                        .foregroundColor(.secondary)
                }
            }
            ProgressView(value: viewModel.progressBarProgress)
                .accentColor(color(for: viewModel.progressBarColorStyle))
        }
    }

    private func color(for colorStyle: ColorStyle) -> Color {
        switch colorStyle {
        case .glucose:
            return glucoseTintColor
        case .warning:
            return guidanceColors.warning
        case .critical:
            return guidanceColors.critical
        case .normal:
            return .primary
        case .dimmed:
            return .secondary
        }
    }


    private var doneButton: some View {
        Button("Done", action: {
            self.didFinish()
        })
    }

}
