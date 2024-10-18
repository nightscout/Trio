import AppIntents
import Foundation

@available(iOS 16.0, *) struct AppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: BolusIntent(),
            phrases: [
                "\(.applicationName) Bolus",
                "Enacts a \(.applicationName) Bolus"
            ]
        )
        AppShortcut(
            intent: ApplyTempPresetIntent(),
            phrases: [
                "Activate \(.applicationName) TempTarget Preset",
                "Activates an available \(.applicationName) TempTarget Preset"
            ]
        )
        AppShortcut(
            intent: CreateAndApplyTempTarget(),
            phrases: [
                "New \(.applicationName) TempTarget",
                "Creates and applies a newly configured \(.applicationName) TempTarget"
            ]
        )
        AppShortcut(
            intent: CancelTempPresetIntent(),
            phrases: [
                "Cancel \(.applicationName) TempTarget",
                "Cancels an active \(.applicationName) TempTarget"
            ]
        )
        AppShortcut(
            intent: ListStateIntent(),
            phrases: [
                "List \(.applicationName) state",
                "Lists different states of \(.applicationName)"
            ]
        )
        AppShortcut(
            intent: AddCarbPresetIntent(),
            phrases: [
                "\(.applicationName) Carbs",
                "Adds carbs to \(.applicationName)"
            ]
        )
        AppShortcut(
            intent: ApplyOverridePresetIntent(),
            phrases: [
                "Activate \(.applicationName) Override Preset",
                "Activates an available \(.applicationName) Override Preset"
            ]
        )
        AppShortcut(
            intent: CancelOverrideIntent(),
            phrases: [
                "Cancel \(.applicationName) Override",
                "Cancels an active \(.applicationName) Override"
            ]
        )
    }
}
