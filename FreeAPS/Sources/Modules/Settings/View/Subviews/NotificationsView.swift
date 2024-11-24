//
//  FeatureSettingsView.swift
//  FreeAPS
//
//  Created by Deniz Cengiz on 26.07.24.
//
import Foundation
import LoopKitUI
import SwiftUI
import Swinject

struct NotificationsView: BaseView {
    let resolver: Resolver

    @ObservedObject var state: Settings.StateModel
    @State var notificationsDisabled = false
    @State var showAlert = false
    @State private var shouldDisplayHint: Bool = false
    @State var hintDetent = PresentationDetent.large
    @State var selectedVerboseHint: String? =
        "Notifications give you important Trio information without requiring you to open the app.\n\nKeep these turned ON in your phone’s settings to ensure you receive Trio Notifications, Critical Alerts, and Time Sensitive Notifications."
    @State var hintLabel: String? = "Manage iOS Preferences"

    @Environment(\.colorScheme) var colorScheme
    var color: LinearGradient {
        colorScheme == .dark ? LinearGradient(
            gradient: Gradient(colors: [
                Color.bgDarkBlue,
                Color.bgDarkerDarkBlue
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

    var body: some View {
        Form {
            Section(
                header: Text("Manage iOS Preferences"),
                content: {
                    manageNotifications
                }
            )
            Section {
                VStack {
                    notificationsEnabledStatus
                    HStack(alignment: .top) {
                        Text(
                            "Notifications give you important Trio information without requiring you to open the app."
                        )
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        Spacer()
                        Button(
                            action: {
                                hintLabel = "Manage iOS Preferences"
                                selectedVerboseHint =
                                    "Notifications give you important Trio information without requiring you to open the app.\n\nKeep these turned ON in your phone’s settings to ensure you receive Trio Notifications, Critical Alerts, and Time Sensitive Notifications."
                                shouldDisplayHint.toggle()
                            },
                            label: {
                                HStack {
                                    Image(systemName: "questionmark.circle")
                                }
                            }
                        ).buttonStyle(BorderlessButtonStyle())
                    }.padding(.top)
                }.padding(.bottom)
            }.listRowBackground(Color.chart)
            Section(
                header: Text("Notification Center"),
                content: {
                    Text("Trio Notifications")
                        .navigationLink(to: .glucoseNotificationSettings, from: self)

                    if #available(iOS 16.2, *) {
                        Text("Live Activity").navigationLink(to: .liveActivitySettings, from: self)
                    }

                    Text("Calendar Events").navigationLink(to: .calendarEventSettings, from: self)
                }
            )
            .listRowBackground(Color.chart)
        }
        .onReceive(
            resolver.resolve(AlertPermissionsChecker.self)!.$notificationsDisabled,
            perform: {
                if notificationsDisabled != $0 {
                    notificationsDisabled = $0
                    if notificationsDisabled {
                        showAlert = true
                    }
                }
            }
        )
        .alert(
            isPresented: self.$showAlert,
            content: { self.notificationReminder() }
        )
        .sheet(isPresented: $shouldDisplayHint) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint,
                hintLabel: hintLabel ?? "",
                hintText: selectedVerboseHint ?? "",
                sheetTitle: "Help"
            )
        }
        .scrollContentBackground(.hidden).background(color)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.automatic)
    }
}

extension NotificationsView {
    func notificationReminder() -> Alert {
        Alert(
            title: Text("\u{2757} Notifications are Required"),
            message: Text(
                "Please authorize notifications by tapping 'Open iOS Settings' > 'Notifications' and enable 'Allow Notifications' for 'Notification Center' and 'Banners' Alerts."
            ),
            dismissButton: .default(Text("Ok"))
        )
    }

    @ViewBuilder private func onOff(_ val: Bool) -> some View {
        if val {
            Text(NSLocalizedString("On", comment: "Notification Setting Status is On"))
        } else {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.critical)
                Text(NSLocalizedString("Off", comment: "Notification Setting Status is Off"))
            }
        }
    }

    private var manageNotifications: some View {
        Button(action: { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }) {
            HStack {
                Text(NSLocalizedString("Open iOS Settings", comment: "Manage Permissions in Settings button text"))
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.gray).font(.footnote)
            }
        }
        .accentColor(.primary)
    }

    private var notificationsEnabledStatus: some View {
        HStack {
            Text(NSLocalizedString("Notifications", comment: "Notifications Status text"))
            Spacer()
            onOff(!notificationsDisabled)
        }
    }
}
