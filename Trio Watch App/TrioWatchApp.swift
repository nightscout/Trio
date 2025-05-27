//
// Trio
// TrioWatchApp.swift
// Created by Deniz Cengiz on 2025-01-05.
// Last edited by Deniz Cengiz on 2025-01-05.
// Most contributions by Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import AppIntents

struct TrioWatchApp: AppIntent {
    static var title: LocalizedStringResource { "Trio Watch App" }

    func perform() async throws -> some IntentResult {
        .result()
    }
}
