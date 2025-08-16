import LoopKitUI

/// Notes on the CGM lifecycle:
/// There are two classes of CGM devices: plugins and non-plugins. Plugins are implemented using
/// LoopKit APIs and include most hardware CGMs like Dexcom G6, G7, Libre, and so on. Non-plugins
/// drivers are implemented directly in Trio, and include the CGM Simulator and Nightscout CGM. For
/// these different CGMs, there are a few different events, handled in different places, that happen to
/// signify a change in the CGM lifecycle.
///
/// Both:
/// - addCGM function invocation: Called by the UI in response to a user clicking the "add CGM" button
///
/// Non-plugins only:
/// - deleteCGM function invocation: Called by the CGM View in response to a user clicking the "delete CGM" button
///
/// Plugins only:
/// - completionNotifyingDidComplete: Called by the CGM driver to signify that Trio should close its UIViewController
/// - cgmManagerOnboarding didCreateCGMManager: Called by the CGM driver after adding a new CGM
/// - cgmManagerWantsDeletion: Called by the CGM driver when the user asks to delete a CGM
/// There are no ordering constraints between completionNotifyingDidComplete and the other two
/// Plugin events (it's up to the implementation of each individual driver). For example, the G7 driver invokes
/// cgmManagerWantsDeletion on the delegate's queue while calling completionNotifyingDidComplete in parallel
/// on the main queue.
///
/// In additinon to having different events for different types of CGMs, the handling of these events is spread out
/// across various state managers, like HomeStateModel, CGMSettingsStateModel, and PluginSource.
///
/// There is CGM state in the HomeStateModel and CGMSettingsStateModel, FetchGlucoseManager, and
/// SettingsManger
///
/// The flow for adding a CGM:
/// - Non-plugin: addCGM (considered onboarded at this point)
/// - Plugin: addCGM -> cgmManagerOnboarding (after success)
///
/// For deleting a CGM:
/// - Non-plugin: deleteCGM (in HomeStateModel and CGMSettingsStateModel)
/// - Plugin: cgmManagerWantsDeletion (in PluginSource)
/// Then, both non-plugin and plugin:  set settings.cgm (in FetchGlucoseManager) ->
///     settingsDidChange (in HomeStateModel and CGMSettingsStateModel)

extension Home.StateModel: CompletionDelegate {
    /// This completion handler is called by both the CGM and the pump
    func completionNotifyingDidComplete(_ notifying: CompletionNotifying) {
        debug(.service, "Completion fired by: \(type(of: notifying))")
        Task {
            // this sleep is because this event and cgmManagerWantsDeletion
            // are called in parallel.
            try await Task.sleep(for: .seconds(0.2))
            await MainActor.run {
                if fetchGlucoseManager.cgmGlucoseSourceType == .none {
                    cgmCurrent = cgmDefaultModel
                }
            }
        }
        shouldDisplayCGMSetupSheet = false
        shouldDisplayPumpSetupSheet = false
    }
}

extension Home.StateModel: CGMManagerOnboardingDelegate {
    func cgmManagerOnboarding(didCreateCGMManager manager: LoopKitUI.CGMManagerUI) {
        settingsManager.settings.cgm = cgmCurrent.type
        settingsManager.settings.cgmPluginIdentifier = cgmCurrent.id
        fetchGlucoseManager.updateGlucoseSource(
            cgmGlucoseSourceType: cgmCurrent.type,
            cgmGlucosePluginId: cgmCurrent.id,
            newManager: manager
        )
        DispatchQueue.main.async {
            self.broadcaster.notify(GlucoseObserver.self, on: .main) {
                $0.glucoseDidUpdate([])
            }
        }
    }

    func cgmManagerOnboarding(didOnboardCGMManager _: LoopKitUI.CGMManagerUI) {
        // nothing to do
    }
}
