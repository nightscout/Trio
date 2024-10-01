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

    @Environment(\.appName) private var appName
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
                header: Text("Notification Center"),
                content: {
                    Section(footer: DescriptiveText(label: String(format: NSLocalizedString("""
                    Notifications give you important %1$@ app information without requiring you to open the app.

                    Keep these turned ON in your phone’s settings to ensure you receive %1$@ Notifications, Critical Alerts, and Time Sensitive Notifications.
                    """, comment: "Alert Permissions descriptive text (1: app name)"), appName)))
                        {
                            manageNotifications
                            notificationsEnabledStatus
                        }
                    Text("Glucose Notifications").navigationLink(to: .glucoseNotificationSettings, from: self)

                    if #available(iOS 16.2, *) {
                        Text("Live Activity").navigationLink(to: .liveActivitySettings, from: self)
                    }

                    Text("Calendar Events").navigationLink(to: .calendarEventSettings, from: self)
                }
            )
            .listRowBackground(Color.chart)
        }
        .onReceive(resolver.resolve(AlertPermissionsChecker.self)!.$notificationsDisabled, perform: {
            notificationsDisabled = $0
        })
        .scrollContentBackground(.hidden).background(color)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.automatic)
    }
}

extension NotificationsView {
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
                Text(NSLocalizedString("Manage Permissions in Settings", comment: "Manage Permissions in Settings button text"))
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
