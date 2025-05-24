//
// Trio
// TrioWatchApp.swift
// Created by Marvin Polscheit on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-04-22.
// Most contributions by Deniz Cengiz and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

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
