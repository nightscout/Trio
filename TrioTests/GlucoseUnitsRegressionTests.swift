import Combine
import CoreData
import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import SwiftUI
import Swinject
import Testing
@testable import Trio
import UIKit

@MainActor
@Suite("Units Limits Units Regression", .serialized) struct UnitsLimitsUnitsRegressionTests {
    let resolver: Resolver
    let broadcaster: RecordingBroadcaster
    let settings: RegressionSettingsManager

    init() async throws {
        let coreDataStack = try await CoreDataStack.createForTests()
        let broadcaster = RecordingBroadcaster()
        self.broadcaster = broadcaster
        let settings = RegressionSettingsManager()
        self.settings = settings
        settings.onSettingsChange = { [broadcaster] newSettings in
            broadcaster.notify(SettingsObserver.self, on: .main) {
                $0.settingsDidChange(newSettings)
            }
        }
        resolver = Assembler([
            StorageAssembly(),
            ServiceAssembly(),
            APSAssembly(),
            NetworkAssembly(),
            UIAssembly(),
            SecurityAssembly(),
            TestAssembly(testContext: coreDataStack.newTaskContext()),
            TestBroadcasterAssembly(broadcaster: broadcaster)
        ]).resolver
    }

    @Test("External unit changes reach the visible page state") func externalUnitChangeUpdatesPageUnits() {
        let state = makeState()
        settings.settings.units = .mmolL

        #expect(state.units == .mmolL)
        #expect(broadcaster.notificationCount == 1)
    }

    @Test(
        "Picker changes update page units without converting the raw threshold"
    ) func pickerChangeUpdatesPageUnitsAndKeepsRawThreshold() {
        let state = makeState()
        state.threshold_setting = 75

        state.unitsIndex = 1

        #expect(settings.settings.units == .mmolL)
        #expect(state.units == .mmolL)
        #expect(state.threshold_setting == 75)
    }

    private func makeState() -> UnitsLimitsSettings.StateModel {
        let state = UnitsLimitsSettings.StateModel()
        state.settingsManager = settings
        state.settings = settings
        state.resolver = resolver
        return state
    }
}

@MainActor
@Suite("Loop Status Reason Units") struct LoopStatusReasonUnitsTests {
    @Test("Existing Eventual BG below-target conversion is preserved") func existingConversion() {
        let output = LoopStatusView.parseReasonConclusion(
            "Eventual BG 80 < 100, but Delta 5 > expectedDelta 2",
            isMmolL: true
        )

        #expect(output.contains("Eventual BG 4.4<5.6"))
        #expect(output.contains("Delta 0.3"))
        #expect(output.contains("expectedDelta 0.1"))
    }

    @Test("Bare Eventual BG comparisons convert every glucose-dimension value") func bareGreaterThan() {
        let output = LoopStatusView.parseReasonConclusion(
            "Eventual BG 180 > 120 but Delta -5 < Exp. Delta 2",
            isMmolL: true
        )

        #expect(output.contains("Eventual BG 10"))
        #expect(output.contains("6.7"))
        #expect(!output.contains("180"))
        #expect(!output.contains("120"))
        #expect(output.contains("Delta -0.3"))
        #expect(output.contains("Exp. Delta 0.1"))
    }

    @Test("Min. Delta and Exp. Delta labels stay intact while their values convert") func minAndExpectedDeltaLabels() {
        let output = LoopStatusView.parseReasonConclusion(
            "Eventual BG 180 > 120 but Min. Delta -5 > Exp. Delta 2",
            isMmolL: true
        )

        #expect(output.contains("Eventual BG 10"))
        #expect(output.contains("6.7"))
        #expect(!output.contains("180"))
        #expect(!output.contains("120"))
        #expect(output.contains("Min. Delta -0.3"))
        #expect(output.contains("Exp. Delta 0.1"))
    }

    @Test("maxDelta and its BG value both convert; the percentage does not") func maxDeltaConversion() {
        let output = LoopStatusView.parseReasonConclusion(
            "maxDelta 37 > 20% of BG 95 - SMB disabled!",
            isMmolL: true
        )

        #expect(output.contains("MaxDelta 2.1"))
        #expect(output.contains("20%"))
        #expect(output.contains("BG 5.3"))
    }

    @Test("Delta label variants convert exactly once") func deltaLabelsConvertOnce() {
        let output = LoopStatusView.parseReasonConclusion(
            "Reason: expectedDelta 2 Delta 5 Exp. Delta -2 Min. Delta -5",
            isMmolL: true
        )

        #expect(output.contains("expectedDelta 0.1"))
        #expect(output.contains(" Delta 0.3"))
        #expect(output.contains("Exp. Delta -0.1"))
        #expect(output.contains("Min. Delta -0.3"))
    }

    @Test("mg/dL reasoning is returned unchanged") func mgdLControl() {
        let input = "Eventual BG 180 > 120 but Min. Delta -0.30 < Exp. Delta 0.2, maxDelta 37 > 20% of BG 95"
        #expect(LoopStatusView.parseReasonConclusion(input, isMmolL: false) == input)
    }

    @Test("Insulin amounts, durations and percentages are not treated as glucose") func nonGlucoseValuesStayUnchanged() {
        let input = "IOB 1.2 U, Temp 30m, 50% basal, 20% of BG"
        #expect(LoopStatusView.parseReasonConclusion(input, isMmolL: true) == input)
    }
}

@MainActor
@Suite("CGM Settings Coordinator Units") struct CGMSettingsCoordinatorUnitsTests {
    @Test("Coordinator applies the unit through the real update entry point") func coordinatorUpdatesPreference() {
        let view = CGMSettings.CGMSettingsView(
            cgmManager: nil,
            bluetoothManager: UnitTestBluetoothStateManager(),
            unit: .mgdL
        )
        let coordinator = view.makeCoordinator()

        #expect(coordinator.displayGlucosePreference.unit == .milligramsPerDeciliter)

        coordinator.updateDisplayGlucoseUnit(.mmolL)

        #expect(coordinator.displayGlucosePreference.unit == .millimolesPerLiter)
    }

    @Test("Coordinator starts in the unit selected by the settings page") func coordinatorHonorsInitialUnit() {
        let view = CGMSettings.CGMSettingsView(
            cgmManager: nil,
            bluetoothManager: UnitTestBluetoothStateManager(),
            unit: .mmolL
        )

        #expect(view.makeCoordinator().displayGlucosePreference.unit == .millimolesPerLiter)
    }
}

@MainActor
@Suite("CGM Settings Hosted Units") struct CGMSettingsHostedUnitsTests {
    @Test(
        "Hosted representable updates the manager's settings preference in place"
    ) func hostedRepresentableUpdatesManagerPreference() throws {
        let manager = UnitRecordingCGMManager()
        let driver = HostedUnitsDriver()
        let hostingController = UIHostingController(
            rootView: HostedCGMSettingsView(
                driver: driver,
                manager: manager,
                bluetoothManager: UnitTestBluetoothStateManager()
            )
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        hostingController.view.frame = window.bounds
        hostingController.view.layoutIfNeeded()

        waitUntil { manager.receivedSettingsViewController != nil }

        let settingsViewController = try #require(manager.receivedSettingsViewController)
        let preference = try #require(settingsViewController.displayGlucosePreference)
        #expect(manager.receivedDisplayGlucosePreference === preference)
        #expect(preference.unit == .milligramsPerDeciliter)

        // Only updateUIViewController mutates the coordinated preference.
        driver.unit = .mmolL
        waitUntil { preference.unit == .millimolesPerLiter }
        #expect(preference.unit == .millimolesPerLiter)
        #expect(manager.receivedDisplayGlucosePreference === preference)

        driver.unit = .mgdL
        waitUntil { preference.unit == .milligramsPerDeciliter }
        #expect(preference.unit == .milligramsPerDeciliter)
    }
}

@MainActor private final class HostedUnitsDriver: ObservableObject {
    @Published var unit: GlucoseUnits = .mgdL
}

private struct HostedCGMSettingsView: View {
    @ObservedObject var driver: HostedUnitsDriver
    let manager: CGMManagerUI
    let bluetoothManager: BluetoothStateManager

    var body: some View {
        NavigationStack {
            CGMSettings.CGMSettingsView(
                cgmManager: manager,
                bluetoothManager: bluetoothManager,
                unit: driver.unit
            )
        }
    }
}

@MainActor private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
}

@MainActor
@Suite("CGM Manager Unit Propagation", .serialized) struct CGMManagerUnitPropagationTests {
    let resolver: Resolver
    let fetchGlucoseManager: BaseFetchGlucoseManager

    init() async throws {
        let coreDataStack = try await CoreDataStack.createForTests()
        resolver = Assembler([
            StorageAssembly(),
            ServiceAssembly(),
            APSAssembly(),
            NetworkAssembly(),
            UIAssembly(),
            SecurityAssembly(),
            TestAssembly(testContext: coreDataStack.newTaskContext())
        ]).resolver
        fetchGlucoseManager = try #require(resolver.resolve(FetchGlucoseManager.self) as? BaseFetchGlucoseManager)
    }

    @Test("A new CGM manager receives the settings unit before it becomes current") func newManagerGetsUnitsBeforeCurrent() {
        let settings = RegressionSettingsManager()
        settings.settings.units = .mgdL
        fetchGlucoseManager.settingsManager = settings

        let manager = UnitRecordingCGMManager()
        var wasCurrentAtUnitChange: Bool?
        manager.onUnitChange = { [weak fetchGlucoseManager, weak manager] in
            wasCurrentAtUnitChange = fetchGlucoseManager?.cgmManager === manager
        }

        fetchGlucoseManager.updateGlucoseSource(
            cgmGlucoseSourceType: .plugin,
            cgmGlucosePluginId: manager.pluginIdentifier,
            newManager: manager
        )

        #expect(manager.units == [.milligramsPerDeciliter])
        #expect(wasCurrentAtUnitChange == false)
    }

    @Test("The active CGM manager receives settings unit changes") func currentManagerGetsSettingsUnitChange() {
        let settings = RegressionSettingsManager()
        settings.settings.units = .mgdL
        fetchGlucoseManager.settingsManager = settings

        let manager = UnitRecordingCGMManager()
        fetchGlucoseManager.updateGlucoseSource(
            cgmGlucoseSourceType: .plugin,
            cgmGlucosePluginId: manager.pluginIdentifier,
            newManager: manager
        )
        manager.removeAllUnitChanges()

        settings.settings.units = .mmolL
        fetchGlucoseManager.settingsDidChange(settings.settings)

        #expect(manager.units == [.millimolesPerLiter])
    }
}

private struct TestBroadcasterAssembly: Assembly {
    let broadcaster: RecordingBroadcaster

    func assemble(container: Container) {
        container.register(Broadcaster.self) { _ in self.broadcaster }
            .inObjectScope(.container)
    }
}

final class RegressionSettingsManager: SettingsManager {
    var settings = TrioSettings() {
        didSet {
            guard oldValue != settings else { return }
            onSettingsChange?(settings)
        }
    }

    var preferences = Preferences()
    var pumpSettings = PumpSettings(insulinActionCurve: 6, maxBolus: 0, maxBasal: 0)
    var onSettingsChange: ((TrioSettings) -> Void)?

    func updateInsulinCurve(_: InsulinType?) {}
}

final class RecordingBroadcaster: Broadcaster {
    private struct WeakObserver {
        weak var value: AnyObject?
    }

    private var observers: [ObjectIdentifier: [WeakObserver]] = [:]
    private(set) var notificationCount = 0

    func register<T>(_ protocolType: T.Type, observer: T) {
        observers[ObjectIdentifier(protocolType), default: []].append(WeakObserver(value: observer as AnyObject))
    }

    func unregister<T>(_ protocolType: T.Type, observer: T) {
        observers[ObjectIdentifier(protocolType)]?.removeAll { $0.value === observer as AnyObject }
    }

    func unregister<T>(_ protocolType: T.Type) {
        observers[ObjectIdentifier(protocolType)] = nil
    }

    func notify<T>(_ protocolType: T.Type, on _: DispatchQueue, block: @escaping (T) -> Void) {
        notificationCount += 1
        for observer in observers[ObjectIdentifier(protocolType)] ?? [] {
            if let value = observer.value as? T {
                block(value)
            }
        }
    }
}

private final class UnitTestBluetoothStateManager: BluetoothStateManager {
    var bluetoothAuthorization: BluetoothAuthorization { .authorized }
    var bluetoothState: BluetoothState { .poweredOn }

    func authorizeBluetooth(_ completion: @escaping (BluetoothAuthorization) -> Void) {
        completion(bluetoothAuthorization)
    }

    func addBluetoothObserver(_: BluetoothObserver, queue _: DispatchQueue) {}
    func removeBluetoothObserver(_: BluetoothObserver) {}
}

private final class UnitRecordingCGMManager: CGMManagerUI {
    static var onboardingImage: UIImage? { nil }

    let pluginIdentifier = "UnitRecordingCGMManager"

    weak var cgmManagerDelegate: CGMManagerDelegate?
    var delegateQueue: DispatchQueue! = DispatchQueue(label: "UnitRecordingCGMManager.delegate")
    let localizedTitle = "Unit Recording CGM"
    let isOnboarded = true
    let inSignalLoss = false
    let isInoperable = false
    let providesBLEHeartbeat = false
    let managedDataInterval: TimeInterval? = nil
    let shouldSyncToRemoteService = false
    let glucoseDisplay: GlucoseDisplayable? = nil
    let cgmManagerStatus = CGMManagerStatus(hasValidSensorSession: false, device: nil)
    var rawState: RawStateValue { [:] }
    var debugDescription: String { localizedTitle }
    var smallImage: UIImage? { nil }
    var cgmStatusHighlight: DeviceStatusHighlight? { nil }
    var cgmLifecycleProgress: DeviceLifecycleProgress? { nil }
    var cgmStatusBadge: DeviceStatusBadge? { nil }
    var onUnitChange: (() -> Void)?

    private let unitLock = NSLock()
    private var recordedUnits: [LoopUnit] = []

    var units: [LoopUnit] {
        unitLock.withLock { recordedUnits }
    }

    func removeAllUnitChanges() {
        unitLock.withLock { recordedUnits.removeAll() }
    }

    func unitDidChange(to displayGlucoseUnit: LoopUnit) {
        onUnitChange?()
        unitLock.withLock { recordedUnits.append(displayGlucoseUnit) }
    }

    init() {}

    required init?(rawState _: RawStateValue) {}

    static func setupViewController(
        bluetoothProvider _: BluetoothProvider,
        displayGlucosePreference _: DisplayGlucosePreference,
        colorPalette _: LoopUIColorPalette,
        allowDebugFeatures _: Bool,
        prefersToSkipUserInteraction _: Bool
    ) -> SetupUIResult<CGMManagerViewController, CGMManagerUI> {
        .createdAndOnboarded(UnitRecordingCGMManager())
    }

    private(set) var receivedDisplayGlucosePreference: DisplayGlucosePreference?
    private(set) var receivedSettingsViewController: StubCGMManagerViewController?

    func settingsViewController(
        bluetoothProvider _: BluetoothProvider,
        displayGlucosePreference: DisplayGlucosePreference,
        colorPalette _: LoopUIColorPalette,
        allowDebugFeatures _: Bool
    ) -> CGMManagerViewController {
        receivedDisplayGlucosePreference = displayGlucosePreference
        let viewController = StubCGMManagerViewController()
        viewController.displayGlucosePreference = displayGlucosePreference
        receivedSettingsViewController = viewController
        return viewController
    }

    func fetchNewDataIfNeeded(_ completion: @escaping (CGMReadingResult) -> Void) {
        completion(.noData)
    }

    func acknowledgeAlert(alertIdentifier _: LoopKit.Alert.AlertIdentifier) async throws {}
    func getSoundBaseURL() -> URL? { nil }
    func getSounds() -> [LoopKit.Alert.Sound] { [] }
}

private final class StubCGMManagerViewController: UIViewController, CGMManagerOnboarding, CompletionNotifying {
    var cgmManagerOnboardingDelegate: CGMManagerOnboardingDelegate?
    var completionDelegate: CompletionDelegate?
    var displayGlucosePreference: DisplayGlucosePreference?
}
