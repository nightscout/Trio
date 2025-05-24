//
// Trio
// CancelTempPresetIntent.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-03-05.
// Most contributions by Pierre L and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

import AppIntents
import Foundation

/// An App Intent that allows users to cancel an active temporary target through the Shortcuts app.
struct CancelTempPresetIntent: AppIntent {
    /// The title displayed for this action in the Shortcuts app.
    static var title: LocalizedStringResource = "Cancel a Temporary Target"

    /// The description displayed for this action in the Shortcuts app.
    static var description = IntentDescription("Cancel Temporary Target.")

    /// Performs the intent action to cancel an active temporary target.
    ///
    /// - Returns: A confirmation dialog indicating that the temporary target has been canceled.
    /// - Throws: An error if the cancellation process fails.
    @MainActor func perform() async throws -> some ProvidesDialog {
        await TempPresetsIntentRequest().cancelTempTarget()
        return .result(
            dialog: IntentDialog(stringLiteral: "Temporary Target canceled")
        )
    }
}
