// Trio
// SnoozeStateModel.swift
// Created by Ivan Valkou on 2021-11-07.

import Observation
import SwiftUI

extension Snooze {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Persisted(key: "UserNotificationsManager.snoozeUntilDate") var snoozeUntilDate: Date = .distantPast
        @ObservationIgnored @Injected() var glucoseStogare: GlucoseStorage!

        var alarm: GlucoseAlarm?

        override func subscribe() {
            alarm = glucoseStogare.alarm
        }
    }
}
