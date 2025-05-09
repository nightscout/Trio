import SwiftUI
import Swinject

enum Screen: Identifiable, Hashable {
    case loading
    case home
    case settings
    case configEditor(file: String)
    case nighscoutConfig
    case nighscoutConfigDirect
    case tidepoolConfig
    case pumpConfig
    case pumpConfigDirect
    case basalProfileEditor
    case isfEditor
    case crEditor
    case targetsEditor
    case treatmentView
    case manualTempBasal
    case dataTable
    case cgm
    case healthkit
    case glucoseNotificationSettings
    case mealSettings
    case iconConfig
    case overrideConfig
    case snooze
    case statistics
    case watch
    case userInterfaceSettings
    case bolusCalculatorConfig
    case dynamicISF
    case calibrations
    case shortcutsConfig
    case devices
    case therapySettings
    case algorithmSettings
    case featureSettings
    case notificationSettings
    case liveActivitySettings
    case liveActivityBottomRowSettings
    case calendarEventSettings
    case contactImage
    case serviceSettings
    case remoteControlConfig
    case autosensSettings
    case smbSettings
    case targetBehavior
    case algorithmAdvancedSettings
    case unitsAndLimits
    case appDiagnostics

    var id: Int { String(reflecting: self).hashValue }
}

extension Screen {
    @ViewBuilder func view(resolver: Resolver) -> some View {
        switch self {
        case .loading:
            ProgressView()
        case .home:
            Home.RootView(resolver: resolver)
        case .settings:
            Settings.RootView(resolver: resolver)
        case let .configEditor(file):
            ConfigEditor.RootView(resolver: resolver, file: file)
        case .nighscoutConfig:
            NightscoutConfig.RootView(resolver: resolver, displayClose: false)
        case .nighscoutConfigDirect:
            NightscoutConfig.RootView(resolver: resolver, displayClose: true)
        case .tidepoolConfig:
            TidepoolStartView(resolver: resolver, state: Settings.StateModel())
        case .pumpConfig:
            PumpConfig.RootView(
                resolver: resolver,
                displayClose: false,
                bluetoothManager: resolver.resolve(BluetoothStateManager.self)!
            )
        case .pumpConfigDirect:
            PumpConfig.RootView(
                resolver: resolver,
                displayClose: true,
                bluetoothManager: resolver.resolve(BluetoothStateManager.self)!
            )
        case .basalProfileEditor:
            BasalProfileEditor.RootView(resolver: resolver)
        case .isfEditor:
            ISFEditor.RootView(resolver: resolver)
        case .crEditor:
            CarbRatioEditor.RootView(resolver: resolver)
        case .targetsEditor:
            TargetsEditor.RootView(resolver: resolver)
        case .treatmentView:
            Treatments.RootView(resolver: resolver)
        case .manualTempBasal:
            ManualTempBasal.RootView(resolver: resolver)
        case .dataTable:
            DataTable.RootView(resolver: resolver)
        case .cgm:
            CGMSettings.RootView(
                resolver: resolver,
                displayClose: false,
                bluetoothManager: resolver.resolve(BluetoothStateManager.self)!
            )
        case .healthkit:
            AppleHealthKit.RootView(resolver: resolver)
        case .glucoseNotificationSettings:
            GlucoseNotificationSettings.RootView(resolver: resolver)
        case .mealSettings:
            MealSettings.RootView(resolver: resolver)
        case .iconConfig:
            IconConfig.RootView(resolver: resolver)
        case .overrideConfig:
            Adjustments.RootView(resolver: resolver)
        case .snooze:
            Snooze.RootView(resolver: resolver)
        case .watch:
            WatchConfig.RootView(resolver: resolver)
        case .statistics:
            Stat.RootView(resolver: resolver)
        case .userInterfaceSettings:
            UserInterfaceSettings.RootView(resolver: resolver)
        case .bolusCalculatorConfig:
            BolusCalculatorConfig.RootView(resolver: resolver)
        case .dynamicISF:
            DynamicSettings.RootView(resolver: resolver)
        case .calibrations:
            Calibrations.RootView(resolver: resolver)
        case .shortcutsConfig:
            ShortcutsConfig.RootView(resolver: resolver)
        case .remoteControlConfig:
            RemoteControlConfig.RootView(resolver: resolver)
        case .devices:
            DevicesView(resolver: resolver, state: Settings.StateModel())
        case .therapySettings:
            TherapySettingsView(resolver: resolver, state: Settings.StateModel())
        case .algorithmSettings:
            AlgorithmSettings(resolver: resolver, state: Settings.StateModel())
        case .featureSettings:
            FeatureSettingsView(resolver: resolver, state: Settings.StateModel())
        case .notificationSettings:
            NotificationsView(resolver: resolver, state: Settings.StateModel())
        case .liveActivitySettings:
            LiveActivitySettings.RootView(resolver: resolver)
        case .liveActivityBottomRowSettings:
            LiveActivityWidgetConfiguration(resolver: resolver, state: LiveActivitySettings.StateModel())
        case .calendarEventSettings:
            CalendarEventSettings.RootView(resolver: resolver)
        case .contactImage:
            ContactImage.RootView(resolver: resolver)
        case .serviceSettings:
            ServicesView(resolver: resolver, state: Settings.StateModel())
        case .autosensSettings:
            AutosensSettings.RootView(resolver: resolver)
        case .smbSettings:
            SMBSettings.RootView(resolver: resolver)
        case .targetBehavior:
            TargetBehavoir.RootView(resolver: resolver)
        case .algorithmAdvancedSettings:
            AlgorithmAdvancedSettings.RootView(resolver: resolver)
        case .unitsAndLimits:
            UnitsLimitsSettings.RootView(resolver: resolver)
        case .appDiagnostics:
            AppDiagnostics.RootView(resolver: resolver)
        }
    }

    func modal(resolver: Resolver) -> Main.Modal {
        .init(screen: self, view: view(resolver: resolver).asAny())
    }
}
