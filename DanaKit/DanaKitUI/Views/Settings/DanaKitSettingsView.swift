import LoopKit
import LoopKitUI
import SwiftUI

struct DanaKitSettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.guidanceColors) private var guidanceColors
    @Environment(\.dismissAction) private var dismiss
    @Environment(\.insulinTintColor) var insulinTintColor

    @ObservedObject var viewModel: DanaKitSettingsViewModel
    @State private var isSharePresented: Bool = false

    var supportedInsulinTypes: [InsulinType]
    var imageName: String

    var removePumpManagerActionSheet: ActionSheet {
        ActionSheet(
            title: Text(LocalizedString("Remove Pump", comment: "Title for Dana-i/RS PumpManager deletion action sheet.")),
            message: Text(LocalizedString(
                "Are you sure you want to stop using Dana-i/RS?",
                comment: "Message for Dana-i/RS PumpManager deletion action sheet"
            )),
            buttons: [
                .destructive(Text(LocalizedString(
                    "Delete pump",
                    comment: "Button text to confirm Dana-i/RS PumpManager deletion"
                ))) {
                    viewModel.stopUsingDana()
                },
                .cancel()
            ]
        )
    }

    var syncPumpTime: ActionSheet {
        ActionSheet(
            title: Text(LocalizedString("Time Change Detected", comment: "Title for pod sync time action sheet.")),
            message: Text(LocalizedString(
                "The time on your pump is different from the current time. Do you want to update the time on your pump to the current time?",
                comment: "Message for pod sync time action sheet"
            )),
            buttons: [
                .default(Text(LocalizedString("Yes, Sync to Current Time", comment: "Button text to confirm pump time sync"))) {
                    self.viewModel.syncPumpTime()
                },
                .cancel(Text(LocalizedString("No, Keep Pump As Is", comment: "Button text to cancel pump time sync")))
            ]
        )
    }

    var blindReservoirCannulaRefill: ActionSheet {
        ActionSheet(title: Text(LocalizedString("Type of refill", comment: "Title for refill action")), buttons: [
            .default(Text(LocalizedString("Cannula only", comment: "Button text to cannula only"))) {
                viewModel.navigateToRefillView(true)
            },
            .default(Text(LocalizedString("Reservoir and cannula", comment: "Button text to Reservoir and cannula"))) {
                viewModel.navigateToRefillView(false)
            },
            .cancel(Text(LocalizedString("Cancel", comment: "Button text to cancel")))
        ])
    }

    var silentTone: ActionSheet {
        ActionSheet(
            title: Text(LocalizedString("Toggle silent tone?", comment: "Title for silent tone action sheet")),
            buttons: [
                .default(Text(
                    viewModel.silentTone ?
                        LocalizedString(
                            "Yes, Disable silent tones",
                            comment: "Button text to disable silent tone"
                        ) :
                        LocalizedString("Yes, Enable silent tones", comment: "Button text to enable silent tone")
                )) {
                    self.viewModel.toggleSilentTone()
                },
                .cancel(Text(LocalizedString("No, Keep as is", comment: "Button text to cancel silent tone")))
            ]
        )
    }

    var bleModeSwitch: ActionSheet {
        ActionSheet(
            title: Text(LocalizedString("Toggle Bluetooth mode", comment: "Title for bluetooth mode action sheet")),
            message: Text(LocalizedString(
                "WARNING: Please don't use this until you've read the documentation",
                comment: "Warning message continuous mode"
            )),
            buttons: [
                .default(Text(LocalizedString(
                    "What is this?",
                    comment: "Button text to get help about Continuous mode"
                ))) {
                    // TODO: Switch to official docs once PR is live
                    openURL(URL(string: "https://bastiaanv.github.io/loopdocs/troubleshooting/dana-heartbeat/")!)
                },
                .default(Text(
                    viewModel.isUsingContinuousMode ?
                        LocalizedString(
                            "Yes, Switch to interactive mode",
                            comment: "Button text to disable continuous mode"
                        ) :
                        LocalizedString(
                            "Yes, Switch to continuous mode",
                            comment: "Button text to enable continuous mode"
                        )
                )) {
                    self.viewModel.toggleBleMode()
                },
                .cancel(Text(LocalizedString("No, Keep as is", comment: "Button text to cancel silent tone")))
            ]
        )
    }

    var disableBolusSync: ActionSheet {
        ActionSheet(
            title: Text(LocalizedString(
                viewModel.isBolusSyncingDisabled ? "Re-enable bolus syncing?" : "Disable bolus syncing?",
                comment: "Title for bolus syncing disable action sheet"
            )),
            buttons: [
                .default(Text(
                    viewModel.isBolusSyncingDisabled ?
                        LocalizedString(
                            "Yes, re-enable bolus syncing",
                            comment: "Button text to re-enable bplus syncing"
                        ) :
                        LocalizedString(
                            "Yes, disable bolus syncing",
                            comment: "Button text to disable bolus syncing"
                        )
                )) {
                    self.viewModel.toggleBolusSyncing()
                },
                .cancel(Text(LocalizedString("No, Keep as is", comment: "Button text to cancel silent tone")))
            ]
        )
    }

    var disconnectReminder: ActionSheet {
        ActionSheet(
            title: Text(LocalizedString("Set reminder for disconnect", comment: "Title disconnect reminder sheet")),
            message: Text(LocalizedString(
                "Do you wish to receive a notification when the pump is longer disconnected for a specific time?",
                comment: "body disconnect reminder sheet"
            )),
            buttons: [
                .default(Text(LocalizedString("Yes, 5 minutes", comment: "Button text to 5 min"))) {
                    viewModel.scheduleDisconnectNotification(.minutes(5))
                },
                .default(Text(LocalizedString("Yes, 15 minutes", comment: "Button text to 15 min"))) {
                    viewModel.scheduleDisconnectNotification(.minutes(15))
                },
                .default(Text(LocalizedString("Yes, 30 minutes", comment: "Button text to 30 min"))) {
                    viewModel.scheduleDisconnectNotification(.minutes(30))
                },
                .default(Text(LocalizedString("Yes, 1 hour", comment: "Button text to 1h"))) {
                    viewModel.scheduleDisconnectNotification(.minutes(60))
                },
                .default(Text(LocalizedString("No, just disconnect", comment: "Button text to just disconnect"))) {
                    viewModel.forceDisconnect()
                },
                .cancel(Text(LocalizedString("Cancel", comment: "Button text to cancel")))
            ]
        )
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    Image(uiImage: UIImage(named: imageName, in: Bundle(for: DanaKitHUDProvider.self), compatibleWith: nil)!)
                        .resizable()
                        .scaledToFit()
                        .padding(.horizontal)
                        .frame(height: 200)
                    Spacer()
                }

                HStack(alignment: .top) {
                    deliveryStatus
                    Spacer()
                    reservoirStatus
                }
                .padding(.bottom, 5)

                if viewModel.showPumpTimeSyncWarning {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedString("Time Change Detected", comment: "title for time change detected notice"))
                            .font(Font.subheadline.weight(.bold))
                        Text(LocalizedString(
                            "The time on your pump is different from the current time. Your pump’s time controls your scheduled therapy settings. Scroll down to Pump Time row to review the time difference and configure your pump.",
                            comment: "description for time change detected notice"
                        ))
                            .font(Font.footnote.weight(.semibold))
                    }.padding(.vertical, 8)
                }
            }

            Section {
                Button(action: {
                    viewModel.suspendResumeButtonPressed()
                }) {
                    HStack {
                        Text($viewModel.basalButtonText.wrappedValue)
                        Spacer()
                        if viewModel.isUpdatingPumpState {
                            ActivityIndicator(isAnimating: .constant(true), style: .medium)
                        }
                    }
                }
                .disabled(viewModel.isUpdatingPumpState || viewModel.isSyncing)

                if viewModel.isTempBasal {
                    Button(action: {
                        viewModel.stopTempBasal()
                    }) {
                        HStack {
                            Text(LocalizedString("Stop temp basal", comment: "Dana settings stop temp basal"))
                            Spacer()
                            if viewModel.isUpdatingPumpState {
                                ActivityIndicator(isAnimating: .constant(true), style: .medium)
                            }
                        }
                    }
                    .disabled(viewModel.isUpdatingPumpState || viewModel.isSyncing)
                }

                Button(action: {
                    viewModel.syncData()
                }) {
                    HStack {
                        Text(LocalizedString("Sync pump data", comment: "DanaKit sync pump"))
                        Spacer()
                        if viewModel.isSyncing {
                            ActivityIndicator(isAnimating: .constant(true), style: .medium)
                        }
                    }
                }
                .disabled(viewModel.isUpdatingPumpState || viewModel.isSyncing)

                if viewModel.isUsingContinuousMode {
                    if !viewModel.isConnected {
                        Button(action: {
                            viewModel.reconnect()
                        }) {
                            HStack {
                                Text(LocalizedString("Reconnect to pump", comment: "DanaKit reconnect"))
                                Spacer()
                                if viewModel.isTogglingConnection {
                                    ActivityIndicator(isAnimating: .constant(true), style: .medium)
                                }
                            }
                        }
                        .disabled(viewModel.isTogglingConnection)
                    } else {
                        Button(action: {
                            viewModel.showingDisconnectReminder = true
                        }) {
                            HStack {
                                Text(LocalizedString("Disconnect from pump", comment: "DanaKit disconnect"))
                                Spacer()
                                if viewModel.isTogglingConnection {
                                    ActivityIndicator(isAnimating: .constant(true), style: .medium)
                                }
                            }
                        }
                        .disabled(viewModel.isTogglingConnection)
                        .actionSheet(isPresented: $viewModel.showingDisconnectReminder) {
                            disconnectReminder
                        }
                    }

                    HStack {
                        Text(LocalizedString("Status", comment: "Text for status")).foregroundColor(Color.primary)
                        Spacer()
                        HStack(spacing: 10) {
                            continuousConnectionStatusText
                            continuousConnectionStatusIcon
                        }
                    }
                }

                HStack {
                    Text(LocalizedString("Last sync", comment: "Text for last sync")).foregroundColor(Color.primary)
                    Spacer()
                    Text(String(viewModel.formatDate(viewModel.lastSync)))
                        .foregroundColor(.secondary)
                }

                if let reservoirAge = viewModel.reservoirAge {
                    HStack {
                        Text(LocalizedString("Reservoir age", comment: "Text for reservoir age")).foregroundColor(Color.primary)
                        Spacer()
                        Text(String(reservoirAge))
                            .foregroundColor(.secondary)
                    }
                    .onLongPressGesture(perform: {
                        viewModel.updateReservoirAge()
                    })
                }

                if let cannulaAge = viewModel.cannulaAge {
                    HStack {
                        Text(LocalizedString("Cannula age", comment: "Text for cannula age")).foregroundColor(Color.primary)
                        Spacer()
                        Text(String(cannulaAge))
                            .foregroundColor(.secondary)
                    }
                    .onLongPressGesture(perform: {
                        viewModel.updateCannulaAge()
                    })
                }

                if let batteryAge = viewModel.batteryAge {
                    HStack {
                        Text(LocalizedString("Battery age", comment: "Text for battery age")).foregroundColor(Color.primary)
                        Spacer()
                        Text(String(batteryAge))
                            .foregroundColor(.secondary)
                    }
                    .onLongPressGesture(perform: {
                        viewModel.updateBatteryAge()
                    })
                }
            }

            Section(header: SectionHeader(label: LocalizedString(
                "Configuration",
                comment: "The title of the configuration section in DanaKit settings"
            )))
                {
                    NavigationLink(destination: InsulinTypeView(
                        initialValue: viewModel.insulinType,
                        supportedInsulinTypes: supportedInsulinTypes,
                        didConfirm: viewModel.didChangeInsulinType
                    )) {
                        HStack {
                            Text(LocalizedString("Insulin Type", comment: "Text for confidence reminders navigation link"))
                                .foregroundColor(Color.primary)
                            Spacer()
                            Text(viewModel.insulinType.brandName)
                                .foregroundColor(.secondary)
                        }
                    }
                    NavigationLink(destination: DanaKitSettingsPumpSpeed(
                        value: Int(viewModel.bolusSpeed.rawValue),
                        didChange: viewModel.didBolusSpeedChanged
                    )) {
                        HStack {
                            Text(LocalizedString("Delivery speed", comment: "Title for delivery speed"))
                                .foregroundColor(Color.primary)
                            Spacer()
                            Text(viewModel.bolusSpeed.format())
                                .foregroundColor(.secondary)
                        }
                    }
                    NavigationLink(destination: viewModel.userOptionsView) {
                        Text(LocalizedString("User options", comment: "Title for user options"))
                            .foregroundColor(Color.primary)
                    }
                    Button(action: {
                        viewModel.showingBlindReservoirCannulaRefill = true
                    }) {
                        HStack {
                            Text(LocalizedString("Reservoir/cannula refill", comment: "Title for reservoir/cannula refill"))
                            Spacer()
                            NavigationLink(
                                destination: viewModel.refillView,
                                isActive: $viewModel.showingReservoirCannulaRefillView
                            ) {
                                EmptyView() }
                                .hidden()
                                .frame(width: 0, height: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: UIFont.systemFontSize, weight: .medium))
                                .opacity(0.35)
                        }
                        .foregroundColor(Color.primary)
                    }
                    .actionSheet(isPresented: $viewModel.showingBlindReservoirCannulaRefill) {
                        blindReservoirCannulaRefill
                    }
                }

            Section(header: SectionHeader(label: LocalizedString(
                "Pump information",
                comment: "The title of the pump information section in DanaKit settings"
            ))) {
                HStack {
                    Text(LocalizedString("Pump name", comment: "Text for Dana pump name")).foregroundColor(Color.primary)
                    Spacer()
                    Text(viewModel.deviceName ?? "")
                        .foregroundColor(.secondary)
                }
                .onLongPressGesture(perform: {
                    viewModel.showingSilentTone = true
                })
                .actionSheet(isPresented: $viewModel.showingSilentTone) {
                    silentTone
                }
                HStack {
                    Text(LocalizedString("Hardware model", comment: "Text for hardware model")).foregroundColor(Color.primary)
                    Spacer()
                    Text(String(viewModel.hardwareModel ?? 0))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text(LocalizedString("Firmware version", comment: "Text for firmware version")).foregroundColor(Color.primary)
                    Spacer()
                    Text(String(viewModel.firmwareVersion ?? 0))
                        .foregroundColor(.secondary)
                }
                .onLongPressGesture(perform: {
                    viewModel.showingBleModeSwitch = true
                })
                .actionSheet(isPresented: $viewModel.showingBleModeSwitch) {
                    bleModeSwitch
                }
                HStack {
                    Text(LocalizedString("Basal profile", comment: "Text for Basal profile")).foregroundColor(Color.primary)
                    Spacer()
                    Text(viewModel.transformBasalProfile(viewModel.basalProfileNumber))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text(LocalizedString("Battery level", comment: "Text for Battery level")).foregroundColor(Color.primary)
                    Spacer()
                    Text(String(viewModel.batteryLevel) + "%")
                        .foregroundColor(.secondary)
                }
                .onLongPressGesture(perform: {
                    viewModel.showingBolusSyncingDisabled = true
                })
                .actionSheet(isPresented: $viewModel.showingBolusSyncingDisabled) {
                    disableBolusSync
                }
            }

            Section(header: SectionHeader(label: LocalizedString(
                "Pump time",
                comment: "The title of the pump time section in DanaKit settings"
            ))) {
                HStack {
                    Text(LocalizedString("Pump time", comment: "Text for pump time"))
                        .foregroundColor(Color.primary)
                    Spacer()
                    if viewModel.showPumpTimeSyncWarning {
                        Image(systemName: "clock.fill")
                            .foregroundColor(guidanceColors.warning)
                    }
                    Text(String(viewModel.formatDate(viewModel.pumpTime)))
                        .foregroundColor(viewModel.showPumpTimeSyncWarning ? guidanceColors.warning : .secondary)
                }
                HStack {
                    Text(LocalizedString("Checked at", comment: "Text for pump time synced at"))
                        .foregroundColor(Color.primary)
                    Spacer()
                    Text(String(viewModel.formatDate(viewModel.pumpTimeSyncedAt)))
                        .foregroundColor(.secondary)
                }

                Toggle(
                    LocalizedString("Nightly pump time sync", comment: "Text for Nightly pump time sync"),
                    isOn: $viewModel.nightlyPumpTimeSync
                )
                .onChange(of: viewModel.nightlyPumpTimeSync) { value in
                    viewModel.updateNightlyPumpTimeSync(value)
                }

                Button(action: {
                    viewModel.showingTimeSyncConfirmation = true
                }) {
                    Text(LocalizedString("Manually sync Pump time", comment: "Label for syncing the time on the pump"))
                        .foregroundColor(.accentColor)
                }
                .disabled(viewModel.isSyncing)
                .actionSheet(isPresented: $viewModel.showingTimeSyncConfirmation) {
                    syncPumpTime
                }
            }

            Section {
                Button(LocalizedString("Share Dana pump logs", comment: "DanaKit share logs")) {
                    self.isSharePresented = true
                }
                .sheet(isPresented: $isSharePresented, onDismiss: {}, content: {
                    ActivityViewController(activityItems: viewModel.getLogs())
                })

                Button(action: {
                    viewModel.showingDeleteConfirmation = true
                }) {
                    Text(LocalizedString("Delete Pump", comment: "Label for PumpManager deletion button"))
                        .foregroundColor(guidanceColors.critical)
                }
                .actionSheet(isPresented: $viewModel.showingDeleteConfirmation) {
                    removePumpManagerActionSheet
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationBarItems(trailing: doneButton)
        .navigationBarTitle(viewModel.pumpModel)
    }

    private var doneButton: some View {
        Button("Done", action: {
            dismiss()
        })
    }

    var reservoirStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedString("Insulin Remaining", comment: "Header for insulin remaining on pod settings screen"))
                .foregroundColor(Color(UIColor.secondaryLabel))
            if let reservoirLevel = viewModel.reservoirLevel {
                HStack {
                    ReservoirView(reservoirLevel: reservoirLevel, fillColor: reservoirColor(reservoirLevel))
                        .frame(width: 23, height: 32)
                    Text(viewModel.reservoirText(for: reservoirLevel))
                        .font(.system(size: 28))
                        .fontWeight(.heavy)
                        .fixedSize()
                }
            }
        }
    }

    var deliveryStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(deliverySectionTitle)
                .foregroundColor(Color(UIColor.secondaryLabel))
            if viewModel.isSuspended {
                HStack(alignment: .center) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 34))
                        .fixedSize()
                        .foregroundColor(viewModel.isSuspended ? guidanceColors.warning : Color.accentColor)
                    Text(LocalizedString(
                        "Insulin\nSuspended",
                        comment: "Text shown in insulin delivery space when insulin suspended"
                    ))
                        .fontWeight(.bold)
                        .fixedSize()
                }
            } else if let basalRate = $viewModel.basalRate.wrappedValue {
                HStack(alignment: .center) {
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(viewModel.basalRateFormatter.string(from: basalRate) ?? "")
                            .font(.system(size: 28))
                            .fontWeight(.heavy)
                            .fixedSize()
                        Text(LocalizedString("U/hr", comment: "Units for showing temp basal rate"))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                HStack(alignment: .center) {
                    Image(systemName: "x.circle.fill")
                        .font(.system(size: 34))
                        .fixedSize()
                        .foregroundColor(guidanceColors.warning)
                    Text(LocalizedString("Unknown", comment: "Text shown in basal rate space when delivery status is unknown"))
                        .fontWeight(.bold)
                        .fixedSize()
                }
            }
        }
    }

    var continuousConnectionStatusText: some View {
        if viewModel.isTogglingConnection {
            if viewModel.isConnected {
                return Text(LocalizedString("Disconnecting...", comment: "DanaKit disconnecting"))
            } else {
                return Text(LocalizedString("Reconnecting...", comment: "DanaKit reconnecting"))
            }
        } else {
            if viewModel.isConnected {
                return Text(LocalizedString("Connected", comment: "DanaKit connected"))
            } else {
                return Text(LocalizedString("Disconnected", comment: "DanaKit disconnected"))
            }
        }
    }

    var continuousConnectionStatusIcon: some View {
        let color = viewModel.isTogglingConnection ? Color.orange : viewModel.isConnected ? Color.green : Color.red

        return Circle()
            .fill(color)
            .frame(width: 10, height: 10)
    }

    var deliverySectionTitle: String {
        if viewModel.isSuspended {
            return LocalizedString("Insulin Delivery", comment: "Title of insulin delivery section")
        } else if viewModel.isTempBasal {
            return LocalizedString("Temp Basal", comment: "Pump Event title for UnfinalizedDose with doseType of .tempBasal")
        } else {
            return LocalizedString("Scheduled Basal", comment: "Title of insulin delivery section")
        }
    }

    private func reservoirColor(_ reservoirLevel: Double) -> Color {
        if reservoirLevel > viewModel.reservoirLevelWarning {
            return insulinTintColor
        }

        if reservoirLevel > 0 {
            return guidanceColors.warning
        }

        return guidanceColors.critical
    }
}

#Preview {
    DanaKitSettingsView(
        viewModel: DanaKitSettingsViewModel(nil, nil),
        supportedInsulinTypes: InsulinType.allCases,
        imageName: "danai"
    )
}
