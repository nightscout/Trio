// Trio
// PropertyPersistentFlags.swift
// Created by Deniz Cengiz on 2025-05-06.

import Foundation

/// Centralized store for app-wide persistent flags backed by property list (.plist) files.
///
/// This class uses the `@PersistedProperty` wrapper to store simple state flags such as
/// onboarding completion, diagnostics sharing preference, and the last cleanup timestamp.
///
/// All values are persisted independently in the app’s documents directory as `.plist` files,
/// and survive app restarts and reinstallations (unless the sandbox is cleared).
///
/// Accessed as a singleton via `PropertyPersistentFlags.shared`.
final class PropertyPersistentFlags {
    static let shared = PropertyPersistentFlags()

    @PersistedProperty(key: "onboardingCompleted") var onboardingCompleted: Bool?

    @PersistedProperty(key: "diagnosticsSharing") var diagnosticsSharingEnabled: Bool?

    @PersistedProperty(key: "lastCleanupDate") var lastCleanupDate: Date?
}
