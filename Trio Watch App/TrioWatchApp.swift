// Trio
// TrioWatchApp.swift
// Created by Jonas Björkert on 2025-05-23.

import AppIntents

struct TrioWatchApp: AppIntent {
    static var title: LocalizedStringResource { "Trio Watch App" }

    func perform() async throws -> some IntentResult {
        .result()
    }
}
