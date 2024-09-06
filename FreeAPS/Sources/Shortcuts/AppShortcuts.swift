import AppIntents
import Foundation

@available(iOS 16.0, *) struct AppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: BolusIntent(),
            phrases: [
                "\(.applicationName) bolus",
                "Enacts a \(.applicationName) Bolus"
            ]
        )
        AppShortcut(
            intent: ApplyTempPresetIntent(),
            phrases: [
                "Activate \(.applicationName) temporary target ?",
                "\(.applicationName) apply a temporary target"
            ]
        )
        AppShortcut(
            intent: ListStateIntent(),
            phrases: [
                "List \(.applicationName) state",
                "\(.applicationName) state"
            ]
        )
        AppShortcut(
            intent: AddCarbPresentIntent(),
            phrases: [
                "Add carbs in \(.applicationName)",
                "\(.applicationName) allows to add carbs"
            ]
        )
        AppShortcut(
            intent: ApplyOverridePresetIntent(),
            phrases: [
                "Activate \(.applicationName) override",
                "Activates an available \(.applicationName) override"
            ]
        )
        AppShortcut(
            intent: CancelOverrideIntent(),
            phrases: [
                "Cancel \(.applicationName) override",
                "Cancels an active \(.applicationName) override"
            ]
        )
    }
}
