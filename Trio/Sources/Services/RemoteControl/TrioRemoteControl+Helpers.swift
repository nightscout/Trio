// Trio
// TrioRemoteControl+Helpers.swift
// Created by Jonas Björkert on 2024-10-22.

import Foundation

extension TrioRemoteControl {
    func logError(_ errorMessage: String, pushMessage: PushMessage? = nil) async {
        var note = errorMessage
        if let pushMessage = pushMessage {
            note += " Details: \(pushMessage.humanReadableDescription())"
        }
        debug(.remoteControl, note)
        await nightscoutManager.uploadNoteTreatment(note: note)
    }
}
