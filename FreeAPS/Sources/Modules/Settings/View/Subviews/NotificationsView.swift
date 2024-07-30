//
//  FeatureSettingsView.swift
//  FreeAPS
//
//  Created by Deniz Cengiz on 26.07.24.
//
import Foundation
import SwiftUI
import Swinject

struct NotificationsView: BaseView {
    let resolver: Resolver

    @ObservedObject var state: Settings.StateModel

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
                    Text("Alerts").navigationLink(to: .notificationsConfig, from: self)
                    Text("TODO: Live Activity Settings View")
                    Text("Calendar Events").navigationLink(to: .calendarEventSettings, from: self)
                }
            )
            .listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden).background(color)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.automatic)
    }
}
