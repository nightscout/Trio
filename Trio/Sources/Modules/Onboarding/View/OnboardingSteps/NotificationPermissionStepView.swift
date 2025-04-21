//
//  NotificationPermissionStepView.swift
//  Trio
//
//  Created by Cengiz Deniz on 18.04.25.
//
import SwiftUI
import UserNotifications

struct NotificationPermissionStepView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Allow Notifications")
                .font(.title3)
                .bold()
                .multilineTextAlignment(.leading)

            Text(
                "Trio can notify of different events when you use it. You must allow Trio to send you notifications to work properly."
            )
            .font(.body)
            .multilineTextAlignment(.leading)
            .foregroundColor(Color.secondary)
            .padding(.bottom)

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "ellipsis.message.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color.bgDarkBlue)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.primary.opacity(0.8)))
                    Text("Receive optional real‑time low/high glucose alerts.")
                        .font(.body)
                        .foregroundColor(.primary)
                }

                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color.bgDarkBlue)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.primary.opacity(0.8)))
                    Text("Be warned of connectivity or looping issues.")
                        .font(.body)
                        .foregroundColor(.primary)
                }

                HStack(spacing: 12) {
                    Image(systemName: "app.badge.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color.bgDarkBlue)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.primary.opacity(0.8)))
                    Text("See a badge count when you need a carb correction.")
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }

            Text("You can change these permissions any time in the iOS Settings app.")
                .font(.footnote)
                .multilineTextAlignment(.leading)
                .foregroundColor(Color.secondary)
                .padding(.top)
        }.padding(.horizontal)
    }
}
