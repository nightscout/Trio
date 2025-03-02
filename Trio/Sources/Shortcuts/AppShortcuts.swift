import AppIntents
import Foundation

struct AppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: BolusIntent(),
            phrases: [
                "\(.applicationName) bolus",
                "Enacts a \(.applicationName) Bolus"
            ],
            shortTitle: "Bolus",
            systemImageName: "syringe.fill"
        )
        AppShortcut(
            intent: ApplyTempPresetIntent(),
            phrases: [
                "Activate \(.applicationName) temporary target ?",
                "\(.applicationName) apply a temporary target"
            ],
            shortTitle: "Temporary Target",
            systemImageName: "target"
        )
        AppShortcut(
            intent: ListStateIntent(),
            phrases: [
                "List \(.applicationName) state",
                "\(.applicationName) state"
            ],
            shortTitle: "List State",
            systemImageName: "list.bullet"
        )
        AppShortcut(
            intent: AddCarbPresetIntent(),
            phrases: [
                "Add carbs in \(.applicationName)",
                "\(.applicationName) allows to add carbs"
            ],
            shortTitle: "Add Carbs",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: ApplyOverridePresetIntent(),
            phrases: [
                "Activate \(.applicationName) override",
                "Activates an available \(.applicationName) override"
            ],
            shortTitle: "Activate Override",
            systemImageName: "clock.arrow.2.circlepath"
        )
        AppShortcut(
            intent: CancelOverrideIntent(),
            phrases: [
                "Cancel \(.applicationName) override",
                "Cancels an active \(.applicationName) override"
            ],
            shortTitle: "Cancel Override",
            systemImageName: "xmark.circle.fill"
        )
        AppShortcut(
            intent: CancelTempPresetIntent(),
            phrases: [
                "Cancel \(.applicationName) temporary target",
                "Cancels an active \(.applicationName) temporary target"
            ],
            shortTitle: "Cancel Temp Target",
            systemImageName: "xmark.circle.fill"
        )
        AppShortcut(
            intent: RestartLiveActivityIntent(),
            phrases: [
                "Restart \(.applicationName) Live Activity",
                "Restarts the Live Activity for \(.applicationName)"
            ],
            shortTitle: "Restart Live Activity",
            systemImageName: "arrow.clockwise.circle.fill"
        )
    }
}
