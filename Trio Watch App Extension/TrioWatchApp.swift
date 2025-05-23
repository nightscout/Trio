// Trio
// TrioWatchApp.swift
// Created by Jonas Björkert on 2025-05-23.

import SwiftUI

@main struct TrioWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TrioMainWatchView()
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            if newScenePhase == .background {
                Task {
                    await WatchLogger.shared.flushPersistedLogs()
                }
            }
        }
    }
}
