//
//  OmniBLESettingsView.swift
//  ViewDev
//
//  Created by Pete Schwamb on 3/8/20.
//  Copyright © 2020 Pete Schwamb. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import HealthKit

struct OmniBLESettingsView: View  {

    @ObservedObject var viewModel: OmniBLESettingsViewModel

    @State private var showingDeleteConfirmation = false

    @State private var showSuspendOptions = false

    @State private var showManualTempBasalOptions = false

    @State private var showSyncTimeOptions = false

    @State private var sendingTestBeepsCommand = false

    @State private var cancelingTempBasal = false

    var supportedInsulinTypes: [InsulinType]

    @Environment(\.guidanceColors) var guidanceColors
    @Environment(\.insulinTintColor) var insulinTintColor
    @Environment(\.colorScheme) var colorScheme

    private var color: LinearGradient {
        colorScheme == .dark ? LinearGradient(
            gradient: Gradient(colors: [
                Color("Background_DarkBlue"),
                Color("Background_DarkerDarkBlue")
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
            :
            LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                startPoint: .top,
                endPoint: .bottom
            )
    }
    
    private var daysRemaining: Int? {
        if case .timeRemaining(let remaining, _) = viewModel.lifeState, remaining > .days(1) {
            return Int(remaining.days)
        }
        return nil
    }
    
    private var hoursRemaining: Int? {
        if case .timeRemaining(let remaining, _) = viewModel.lifeState, remaining > .hours(1) {
            return Int(remaining.hours.truncatingRemainder(dividingBy: 24))
        }
        return nil
    }
    
    private var minutesRemaining: Int? {
        if case .timeRemaining(let remaining, _) = viewModel.lifeState, remaining < .hours(2) {
            return Int(remaining.minutes.truncatingRemainder(dividingBy: 60))
        }
        return nil
    }
    
    func timeComponent(value: Int, units: String) -> some View {
        Group {
            Text(String(value)).font(.system(size: 28)).fontWeight(.heavy)
                .foregroundColor(viewModel.podOk ? .primary : .secondary)
            Text(units).foregroundColor(.secondary)
        }
    }
    
    var lifecycleProgress: some View {
        VStack(spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(self.viewModel.lifeState.localizedLabelText)
                    .foregroundColor(self.viewModel.lifeState.labelColor(using: guidanceColors))
                Spacer()
                daysRemaining.map { (days) in
                    timeComponent(value: days, units: days == 1 ?
                                  LocalizedString("day", comment: "Unit for singular day in pod life remaining") :
                                    LocalizedString("days", comment: "Unit for plural days in pod life remaining"))
                }
                hoursRemaining.map { (hours) in
                    timeComponent(value: hours, units: hours == 1 ?
                                  LocalizedString("hour", comment: "Unit for singular hour in pod life remaining") :
                                    LocalizedString("hours", comment: "Unit for plural hours in pod life remaining"))
                }
                minutesRemaining.map { (minutes) in
                    timeComponent(value: minutes, units: minutes == 1 ?
                                  LocalizedString("minute", comment: "Unit for singular minute in pod life remaining") :
                                    LocalizedString("minutes", comment: "Unit for plural minutes in pod life remaining"))
                }
            }
            ProgressView(progress: CGFloat(self.viewModel.lifeState.progress)).accentColor(self.viewModel.lifeState.progressColor(guidanceColors: guidanceColors))
        }
    }
    
    func cancelDelete() {
        showingDeleteConfirmation = false
    }
    
    
    var deliverySectionTitle: String {
        if self.viewModel.isScheduledBasal {
            return LocalizedString("Scheduled Basal", comment: "Title of insulin delivery section")
        } else {
            return LocalizedString("Insulin Delivery", comment: "Title of insulin delivery section")
        }
    }
    
    var deliveryStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(deliverySectionTitle)
                .foregroundColor(Color(UIColor.secondaryLabel))
            if viewModel.podOk, viewModel.isSuspendedOrResuming {
                HStack(alignment: .center) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 34))
                        .fixedSize()
                        .foregroundColor(viewModel.suspendResumeButtonColor(guidanceColors: guidanceColors))
                    FrameworkLocalText("Insulin\nSuspended", comment: "Text shown in insulin delivery space when insulin suspended")
                        .fontWeight(.bold)
                        .fixedSize()
                }
            } else if let basalRate = self.viewModel.basalDeliveryRate {
                HStack(alignment: .center) {
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(self.viewModel.basalRateFormatter.string(from: basalRate) ?? "")
                            .font(.system(size: 28))
                            .fontWeight(.heavy)
                            .fixedSize()
                        FrameworkLocalText("U/hr", comment: "Units for showing temp basal rate").foregroundColor(.secondary)
                    }
                }
            } else {
                HStack(alignment: .center) {
                    Image(systemName: "x.circle.fill")
                        .font(.system(size: 34))
                        .fixedSize()
                        .foregroundColor(guidanceColors.critical)
                    FrameworkLocalText("No\nDelivery", comment: "Text shown in insulin remaining space when no pod is paired")
                        .fontWeight(.bold)
                        .fixedSize()
                }
            }
        }
    }
    
    func reservoir(filledPercent: CGFloat, fillColor: Color) -> some View {
        ZStack(alignment: Alignment(horizontal: .center, vertical: .center)) {
            GeometryReader { geometry in
                let offset = geometry.size.height * 0.05
                let fillHeight = geometry.size.height * 0.81
                Rectangle()
                    .fill(fillColor)
                    .mask(
                        Image(frameworkImage: "pod_reservoir_mask_swiftui")
                            .resizable()
                            .scaledToFit()
                    )
                    .mask(
                        Rectangle().path(in: CGRect(x: 0, y: offset + fillHeight - fillHeight * filledPercent, width: geometry.size.width, height: fillHeight * filledPercent))
                    )
            }
            Image(frameworkImage: "pod_reservoir_swiftui")
                .renderingMode(.template)
                .resizable()
                .foregroundColor(fillColor)
                .scaledToFit()
        }.frame(width: 23, height: 32)
    }
    
    
    var reservoirStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedString("Insulin Remaining", comment: "Header for insulin remaining on pod settings screen"))
                .foregroundColor(Color(UIColor.secondaryLabel))
            HStack {
                if let podError = viewModel.podError {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 34))
                        .fixedSize()
                        .foregroundColor(guidanceColors.critical)

                    Text(podError).fontWeight(.bold)
                } else if let reservoirLevel = viewModel.reservoirLevel, let reservoirLevelHighlightState = viewModel.reservoirLevelHighlightState {
                    reservoir(filledPercent: CGFloat(reservoirLevel.percentage), fillColor: reservoirColor(for: reservoirLevelHighlightState))
                    Text(viewModel.reservoirText(for: reservoirLevel))
                        .font(.system(size: 28))
                        .fontWeight(.heavy)
                        .fixedSize()
                } else {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 34))
                        .fixedSize()
                        .foregroundColor(guidanceColors.warning)
                    
                    FrameworkLocalText("No Pod", comment: "Text shown in insulin remaining space when no pod is paired").fontWeight(.bold)
                }
                
            }
        }
    }

    var manualTempBasalRow: some View {
        Button(action: {
            self.manualBasalTapped()
        }) {
            FrameworkLocalText("Set Temporary Basal Rate", comment: "Button title to set temporary basal rate")
        }
        .sheet(isPresented: $showManualTempBasalOptions) {
            ManualTempBasalEntryView(
                enactBasal: { rate, duration, completion in
                    viewModel.runTemporaryBasalProgram(unitsPerHour: rate, for: duration) { error in
                        completion(error)
                        if error == nil {
                            showManualTempBasalOptions = false
                        }
                    }
                },
                didCancel: {
                    showManualTempBasalOptions = false
                },
                allowedRates: viewModel.allowedTempBasalRates
            )
        }
    }


    func suspendResumeRow() -> some View {
        HStack {
            Button(action: {
                self.suspendResumeTapped()
            }) {
                HStack {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(viewModel.suspendResumeButtonColor(guidanceColors: guidanceColors))
                    Text(viewModel.suspendResumeActionText)
                        .foregroundColor(viewModel.suspendResumeActionColor())
                }
            }
            .actionSheet(isPresented: $showSuspendOptions) {
                suspendOptionsActionSheet
            }
            Spacer()
            if viewModel.basalTransitioning {
                ActivityIndicator(isAnimating: .constant(true), style: .medium)
            }
        }
    }
    
    var headerImage: some View {
        VStack(alignment: .center) {
            Image(frameworkImage: "Pod")
                .resizable()
                .aspectRatio(contentMode: ContentMode.fit)
                .frame(height: 100)
                .padding(.horizontal)
        }.frame(maxWidth: .infinity)
    }
    
    var body: some View {
        List {
            Section() {
                VStack(alignment: .trailing) {
                    Button(action: {
                        sendingTestBeepsCommand = true
                        viewModel.playTestBeeps { _ in
                            sendingTestBeepsCommand = false
                        }
                    }) {
                        Image(systemName: "speaker.wave.2.circle")
                            .imageScale(.large)
                            .foregroundColor(viewModel.podConnected ? .accentColor : .secondary)
                            .padding(.top,5)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!viewModel.podConnected || sendingTestBeepsCommand)

                    headerImage

                    lifecycleProgress

                    HStack(alignment: .top) {
                        deliveryStatus
                        Spacer()
                        reservoirStatus
                    }
                    if let faultAction = viewModel.recoveryText {
                        Divider()
                        Text(faultAction)
                            .font(Font.footnote.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let notice = viewModel.notice {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(notice.title)
                            .font(Font.subheadline.weight(.bold))
                        Text(notice.description)
                            .font(Font.footnote.weight(.semibold))
                    }.padding(.vertical, 8)
                }
            }.listRowBackground(Color("Chart"))

            Section(header: SectionHeader(label: LocalizedString("Activity", comment: "Section header for activity section"))) {
                suspendResumeRow()
                    .disabled(!self.viewModel.podOk)
                if self.viewModel.podOk, case .suspended(let suspendDate) = self.viewModel.basalDeliveryState {
                    HStack {
                        FrameworkLocalText("Suspended At", comment: "Label for suspended at time")
                        Spacer()
                        Text(self.viewModel.timeFormatter.string(from: suspendDate))
                            .foregroundColor(Color.secondary)
                    }
                }
            }.listRowBackground(Color("Chart"))

            Section() {
                if let manualTempRemaining = self.viewModel.manualBasalTimeRemaining, let remainingText = self.viewModel.timeRemainingFormatter.string(from: manualTempRemaining) {
                    HStack {
                        if cancelingTempBasal {
                            ProgressView()
                                .padding(.trailing)
                        } else {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(guidanceColors.warning)
                        }
                        Button(action: {
                            self.cancelManualBasal()
                        }) {
                            FrameworkLocalText("Cancel Manual Basal", comment: "Button title to cancel manual basal")
                        }
                    }
                    HStack {
                        FrameworkLocalText("Remaining", comment: "Label for remaining time of manual basal")
                        Spacer()
                        Text(remainingText)
                            .foregroundColor(.secondary)
                    }
                } else {
                    manualTempBasalRow
                }
            }.listRowBackground(Color("Chart"))
            .disabled(cancelingTempBasal || !self.viewModel.podOk)

            Section() {
                HStack {
                    FrameworkLocalText("Pod Activated", comment: "Label for pod insertion row")
                    Spacer()
                    Text(self.viewModel.activatedAtString)
                        .foregroundColor(Color.secondary)
                }

                HStack {
                    if let expiresAt = viewModel.expiresAt, expiresAt < Date() {
                        FrameworkLocalText("Pod Expired", comment: "Label for pod expiration row, past tense")
                    } else {
                        FrameworkLocalText("Pod Expires", comment: "Label for pod expiration row")
                    }
                    Spacer()
                    Text(self.viewModel.expiresAtString)
                        .foregroundColor(Color.secondary)
                }

                if let podDetails = self.viewModel.podDetails {
                    NavigationLink(destination: PodDetailsView(podDetails: podDetails, title: LocalizedString("Pod Details", comment: "title for pod details page"))) {
                        FrameworkLocalText("Pod Details", comment: "Text for pod details disclosure row")
                            .foregroundColor(Color.primary)
                    }
                } else {
                    HStack {
                        FrameworkLocalText("Pod Details", comment: "Text for pod details disclosure row")
                        Spacer()
                        Text("—")
                            .foregroundColor(Color.secondary)
                    }
                }

                if let previousPodDetails = viewModel.previousPodDetails {
                    NavigationLink(destination: PodDetailsView(podDetails: previousPodDetails, title: LocalizedString("Previous Pod", comment: "title for previous pod page"))) {
                        FrameworkLocalText("Previous Pod Details", comment: "Text for previous pod details row")
                            .foregroundColor(Color.primary)
                    }
                } else {
                    HStack {
                        FrameworkLocalText("Previous Pod Details", comment: "Text for previous pod details row")
                        Spacer()
                        Text("—")
                            .foregroundColor(Color.secondary)
                    }
                }
            }.listRowBackground(Color("Chart"))

            Section() {
                Button(action: {
                    self.viewModel.navigateTo?(self.viewModel.lifeState.nextPodLifecycleAction)
                }) {
                    Text(self.viewModel.lifeState.nextPodLifecycleActionDescription)
                        .foregroundColor(self.viewModel.lifeState.nextPodLifecycleActionColor)
                }
            }.listRowBackground(Color("Chart"))

            Section(header: SectionHeader(label: LocalizedString("Configuration", comment: "Section header for configuration section")))
            {
                NavigationLink(destination:
                                NotificationSettingsView(
                                    dateFormatter: self.viewModel.dateFormatter,
                                    expirationReminderDefault: self.$viewModel.expirationReminderDefault,
                                    scheduledReminderDate: self.viewModel.expirationReminderDate,
                                    allowedScheduledReminderDates: self.viewModel.allowedScheduledReminderDates,
                                    lowReservoirReminderValue: self.viewModel.lowReservoirAlertValue,
                                    onSaveScheduledExpirationReminder: self.viewModel.saveScheduledExpirationReminder,
                                    onSaveLowReservoirReminder: self.viewModel.saveLowReservoirReminder))
                {
                    FrameworkLocalText("Notification Settings", comment: "Text for pod details disclosure row").foregroundColor(Color.primary)
                }
                NavigationLink(destination: BeepPreferenceSelectionView(initialValue: viewModel.beepPreference, onSave: viewModel.setConfirmationBeeps)) {
                    HStack {
                        FrameworkLocalText("Confidence Reminders", comment: "Text for confidence reminders navigation link")
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(viewModel.beepPreference.title)
                            .foregroundColor(.secondary)
                    }
                }
                NavigationLink(destination: SilencePodSelectionView(initialValue: viewModel.silencePodPreference, onSave: viewModel.setSilencePod)) {
                    HStack {
                        FrameworkLocalText("Silence Pod", comment: "Text for silence pod navigation link")
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(viewModel.silencePodPreference.title)
                            .foregroundColor(.secondary)
                    }
                }
                NavigationLink(destination: InsulinTypeSetting(initialValue: viewModel.insulinType, supportedInsulinTypes: supportedInsulinTypes, allowUnsetInsulinType: false, didChange: viewModel.didChangeInsulinType)) {
                    HStack {
                        FrameworkLocalText("Insulin Type", comment: "Text for insulin type navigation link").foregroundColor(Color.primary)
                        if let currentTitle = viewModel.insulinType?.brandName {
                            Spacer()
                            Text(currentTitle)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }.listRowBackground(Color("Chart"))

            Section() {
                HStack {
                    FrameworkLocalText("Pump Time", comment: "The title of the command to change pump time zone")
                    Spacer()
                    if viewModel.isClockOffset {
                        Image(systemName: "clock.fill")
                            .foregroundColor(guidanceColors.warning)
                    }
                    TimeView(timeZone: viewModel.timeZone)
                        .foregroundColor( viewModel.isClockOffset ? guidanceColors.warning : nil)
                }
                if viewModel.synchronizingTime {
                    HStack {
                        FrameworkLocalText("Adjusting Pump Time...", comment: "Text indicating ongoing pump time synchronization")
                            .foregroundColor(.secondary)
                        Spacer()
                        ActivityIndicator(isAnimating: .constant(true), style: .medium)
                    }
                } else if self.viewModel.timeZone != TimeZone.currentFixed {
                    Button(action: {
                        showSyncTimeOptions = true
                    }) {
                        FrameworkLocalText("Sync to Current Time", comment: "The title of the command to change pump time zone")
                    }
                    .actionSheet(isPresented: $showSyncTimeOptions) {
                        syncPumpTimeActionSheet
                    }
                }
            }.listRowBackground(Color("Chart"))

            Section() {
                NavigationLink(destination: PodDiagnosticsView(
                    title: LocalizedString("Pod Diagnostics", comment: "Title for the pod diagnostic view"),
                    viewModel: viewModel))
                {
                    FrameworkLocalText("Pod Diagnostics", comment: "Text for pod diagnostics row")
                        .foregroundColor(Color.primary)
                }
            }.listRowBackground(Color("Chart"))

            if self.viewModel.lifeState.allowsPumpManagerRemoval {
                Section() {
                    Button(action: {
                        self.showingDeleteConfirmation = true
                    }) {
                        FrameworkLocalText("Switch to other insulin delivery device", comment: "Label for PumpManager deletion button")
                            .foregroundColor(guidanceColors.critical)
                    }
                    .actionSheet(isPresented: $showingDeleteConfirmation) {
                        removePumpManagerActionSheet
                    }
                }.listRowBackground(Color("Chart"))
            }
        }.background(color)
        .alert(isPresented: $viewModel.alertIsPresented, content: { alert(for: viewModel.activeAlert!) })
        .insetGroupedListStyle()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    self.viewModel.doneTapped()
                } label: {
                    Text("Close")
                }

            }
        }
        .navigationBarTitle(self.viewModel.viewTitle)
    }

    var syncPumpTimeActionSheet: ActionSheet {
        ActionSheet(title: FrameworkLocalText("Time Change Detected", comment: "Title for pod sync time action sheet."), message: FrameworkLocalText("The time on your pump is different from the current time. Do you want to update the time on your pump to the current time?", comment: "Message for pod sync time action sheet"), buttons: [
            .default(FrameworkLocalText("Yes, Sync to Current Time", comment: "Button text to confirm pump time sync")) {
                self.viewModel.changeTimeZoneTapped()
            },
            .cancel(FrameworkLocalText("No, Keep Pump As Is", comment: "Button text to cancel pump time sync"))
        ])
    }
    
    var removePumpManagerActionSheet: ActionSheet {
        ActionSheet(title: FrameworkLocalText("Remove Pump", comment: "Title for Omnipod DASH PumpManager deletion action sheet."), message: FrameworkLocalText("Are you sure you want to stop using Omnipod DASH?", comment: "Message for Omnipod DASH PumpManager deletion action sheet"), buttons: [
            .destructive(FrameworkLocalText("Delete Omnipod DASH", comment: "Button text to confirm Omnipod DASH PumpManager deletion")) {
                self.viewModel.stopUsingOmnipodDashTapped()
            },
            .cancel()
        ])
    }
    
    var suspendOptionsActionSheet: ActionSheet {
        ActionSheet(
            title: FrameworkLocalText("Suspend Delivery", comment: "Title for suspend duration selection action sheet"),
            message: FrameworkLocalText("Insulin delivery will be stopped until you resume manually. When would you like Loop to remind you to resume delivery?", comment: "Message for suspend duration selection action sheet"),
            buttons: [
                .default(FrameworkLocalText("30 minutes", comment: "Button text for 30 minute suspend duration"), action: { self.viewModel.suspendDelivery(duration: .minutes(30)) }),
                .default(FrameworkLocalText("1 hour", comment: "Button text for 1 hour suspend duration"), action: { self.viewModel.suspendDelivery(duration: .hours(1)) }),
                .default(FrameworkLocalText("1 hour 30 minutes", comment: "Button text for 1 hour 30 minute suspend duration"), action: { self.viewModel.suspendDelivery(duration: .hours(1.5)) }),
                .default(FrameworkLocalText("2 hours", comment: "Button text for 2 hour suspend duration"), action: { self.viewModel.suspendDelivery(duration: .hours(2)) }),
                .cancel()
            ])
    }

    func suspendResumeTapped() {
        switch self.viewModel.basalDeliveryState {
        case .active, .tempBasal:
            showSuspendOptions = true
        case .suspended:
            self.viewModel.resumeDelivery()
        default:
            break
        }
    }

    func manualBasalTapped() {
        showManualTempBasalOptions = true
    }

    func cancelManualBasal() {
        cancelingTempBasal = true
        viewModel.runTemporaryBasalProgram(unitsPerHour: 0, for: 0) { error in
            cancelingTempBasal = false
            if let error = error {
                self.viewModel.activeAlert = .cancelManualBasalError(error)
            }
        }
    }

    
    private func errorText(_ error: Error) -> String {
        if let error = error as? LocalizedError {
            return [error.localizedDescription, error.recoverySuggestion].compactMap{$0}.joined(separator: ". ")
        } else {
            return error.localizedDescription
        }
    }
    
    private func alert(for alert: DashSettingsViewAlert) -> SwiftUI.Alert {
        switch alert {
        case .suspendError(let error):
            return SwiftUI.Alert(
                title: Text("Failed to Suspend Insulin Delivery", comment: "Alert title for suspend error"),
                message: Text(errorText(error))
            )
            
        case .resumeError(let error):
            return SwiftUI.Alert(
                title: Text("Failed to Resume Insulin Delivery", comment: "Alert title for resume error"),
                message: Text(errorText(error))
            )
            
        case .syncTimeError(let error):
            return SwiftUI.Alert(
                title: Text("Failed to Set Pump Time", comment: "Alert title for time sync error"),
                message: Text(errorText(error))
            )

        case .cancelManualBasalError(let error):
            return SwiftUI.Alert(
                title: Text("Failed to Cancel Manual Basal", comment: "Alert title for failing to cancel manual basal error"),
                message: Text(errorText(error))
            )

        }
    }

    func reservoirColor(for reservoirLevelHighlightState: ReservoirLevelHighlightState) -> Color {
        switch reservoirLevelHighlightState {
        case .normal:
            return insulinTintColor
        case .warning:
            return guidanceColors.warning
        case .critical:
            return guidanceColors.critical
        }
    }
}
