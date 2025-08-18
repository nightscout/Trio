//
//  SetupCompleteView.swift
//  OmniKit
//
//  Created by Pete Schwamb on 3/2/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct SetupCompleteView: View {
    
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.appName) private var appName

    
    private var onSaveScheduledExpirationReminder: ((_ selectedDate: Date?, _ completion: @escaping (_ error: Error?) -> Void) -> Void)?
    private var didFinish: () -> Void
    private var didRequestDeactivation: () -> Void
    private var dateFormatter: DateFormatter

    @State private var scheduledReminderDate: Date?

    @State private var scheduleReminderDateEditViewIsShown: Bool = false

    var allowedDates: [Date]

    init(scheduledReminderDate: Date?, dateFormatter: DateFormatter, allowedDates: [Date], onSaveScheduledExpirationReminder: ((_ selectedDate: Date?, _ completion: @escaping (_ error: Error?) -> Void) -> Void)?, didFinish: @escaping () -> Void, didRequestDeactivation: @escaping () -> Void)
    {
        self._scheduledReminderDate = State(initialValue: scheduledReminderDate)
        self.dateFormatter = dateFormatter
        self.allowedDates = allowedDates
        self.onSaveScheduledExpirationReminder = onSaveScheduledExpirationReminder
        self.didFinish = didFinish
        self.didRequestDeactivation = didRequestDeactivation
    }
    
    var body: some View {
        GuidePage(content: {
            VStack {
                LeadingImage("Pod")
                Text(String(format: LocalizedString("Your Pod is ready for use.\n\n%1$@ will remind you to change your pod before it expires. You can change this to a time convenient for you.", comment: "Format string for instructions for setup complete view. (1: app name)"), appName))
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                VStack(alignment: .leading) {
                    Text(LocalizedString("Scheduled Reminder", comment: "Scheduled reminder card title on SetupCompleteView"))
                    Divider()
                    NavigationLink(
                        destination: ScheduledExpirationReminderEditView(
                            scheduledExpirationReminderDate: scheduledReminderDate,
                            allowedDates: allowedDates,
                            dateFormatter: dateFormatter,
                            onSave: { (newDate, completion) in
                                onSaveScheduledExpirationReminder?(newDate) { (error) in
                                    if error == nil {
                                        scheduledReminderDate = newDate
                                    }
                                    completion(error)
                                }
                            },
                            onFinish: { scheduleReminderDateEditViewIsShown = false }),
                        isActive: $scheduleReminderDateEditViewIsShown)
                    {
                        RoundedCardValueRow(
                            label: LocalizedString("Time", comment: "Label for expiration reminder row"),
                            value: scheduledReminderDateString(scheduledReminderDate),
                            highlightValue: false
                        )
                    }
                }
            }
            .padding(.bottom, 8)
            .accessibility(sortPriority: 1)
        }) {
            Button(action: {
                didFinish()
            }) {
                Text(LocalizedString("Finish Setup", comment: "Action button title to continue at Setup Complete"))
                    .actionButtonStyle(.primary)
            }
            .padding()
            .background(Color(UIColor.systemBackground))
            .zIndex(1)
        }
        .animation(.default)
        .navigationBarTitle(LocalizedString("Setup Complete", comment: "Title of SetupCompleteView"), displayMode: .automatic)
    }
    
    private func scheduledReminderDateString(_ scheduledDate: Date?) -> String {
        if let scheduledDate = scheduledDate {
            return dateFormatter.string(from: scheduledDate)
        } else {
            return LocalizedString("No Reminder", comment: "Value text for no expiration reminder")
        }
    }
}

struct SetupCompleteView_Previews: PreviewProvider {
    static var previews: some View {
        SetupCompleteView(
            scheduledReminderDate: Date(),
            dateFormatter: DateFormatter(),
            allowedDates: [Date()],
            onSaveScheduledExpirationReminder: { (date, completion) in
            },
            didFinish: {
            },
            didRequestDeactivation: {
            }
        )
    }
}
