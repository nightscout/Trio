//
// Trio
// SnoozeStateModel.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

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
