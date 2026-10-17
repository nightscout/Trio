import Foundation
import SwiftUI
import Swinject
import UIKit

/// The main onboarding view that manages navigation between onboarding steps.
extension Onboarding {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State private var navigationDirection: OnboardingNavigationDirection = .forward
        let onboardingManager: OnboardingManager
        let wasMigrationSuccessful: Bool

        // Step management
        @State private var showingChapterCompletion: OnboardingChapter? = nil

        @State private var currentStep: OnboardingStep = .welcome
        @State private var currentStartupSubstep: StartupSubstep = .startupGuide
        @State private var currentCloudRestoreSubstep: CloudRestoreSubstep = .choice
        @State private var currentDeliverySubstep: DeliveryLimitSubstep = .maxIOB
        @State private var currentAlgorithmSettingsOverviewSubstep: AlgorithmSettingsOverviewSubstep = .contents
        @State private var currentAutosensSubstep: AutosensSettingsSubstep = .autosensMin
        @State private var currentSMBSubstep: SMBSettingsSubstep = .enableSMBAlways
        @State private var currentTargetBehaviorSubstep: TargetBehaviorSubstep = .highTempTargetRaisesSensitivity

        private var currentChapter: OnboardingChapter {
            if let chapter = showingChapterCompletion { return chapter }
            switch currentStep {
            case .basalRates,
                 .carbRatio,
                 .glucoseTarget,
                 .insulinSensitivity,
                 .unitSelection:
                return .therapySettings
            case .deliveryLimits:
                return .deliveryLimits
            case .algorithmSettings,
                 .autosensSettings,
                 .smbSettings,
                 .targetBehavior:
                return .algorithmSettings
            case .bluetooth,
                 .completed,
                 .notifications:
                return .permissionRequests
            default:
                return .importSettings
            }
        }

        private var chapterProgress: CGFloat {
            if showingChapterCompletion != nil || currentStep == .completed { return 1 }
            switch currentStep {
            case .cloudRestore:
                return currentCloudRestoreSubstep == .choice ? 0.5 : 1
            case .basalRates,
                 .carbRatio,
                 .glucoseTarget,
                 .insulinSensitivity,
                 .unitSelection:
                let steps: [OnboardingStep] = [.unitSelection, .glucoseTarget, .basalRates, .carbRatio, .insulinSensitivity]
                return CGFloat((steps.firstIndex(of: currentStep) ?? 0) + 1) / CGFloat(steps.count)
            case .deliveryLimits:
                return CGFloat(currentDeliverySubstep.rawValue + 1) / CGFloat(DeliveryLimitSubstep.allCases.count)
            case .algorithmSettings,
                 .autosensSettings,
                 .smbSettings,
                 .targetBehavior:
                let autosens = state.filteredAutosensSettingsSubsteps
                let smb = SMBSettingsSubstep.allCases.filter {
                    !state.enableSMBAlways || $0 == .enableSMBAlways || $0.rawValue >= SMBSettingsSubstep
                        .allowSMBWithHighTempTarget.rawValue
                }
                let overviewCount = AlgorithmSettingsOverviewSubstep.allCases.count
                let count = overviewCount + autosens.count + smb.count + TargetBehaviorSubstep.allCases.count
                let index: Int
                switch currentStep {
                case .algorithmSettings:
                    index = currentAlgorithmSettingsOverviewSubstep.rawValue
                case .autosensSettings:
                    index = overviewCount + (autosens.firstIndex(of: currentAutosensSubstep) ?? 0)
                case .smbSettings:
                    index = overviewCount + autosens.count + (smb.firstIndex(of: currentSMBSubstep) ?? 0)
                default:
                    index = overviewCount + autosens.count + smb.count + currentTargetBehaviorSubstep.rawValue
                }
                return CGFloat(index + 1) / CGFloat(count)
            case .notifications:
                return 0.5
            case .bluetooth:
                return 1
            default:
                return 0
            }
        }

        private var shouldDisableNextButton: Bool {
            state
                .restoreInProgress ||
                (currentStep == .cloudRestore && currentCloudRestoreSubstep == .backups && state.pendingCloudRestore == nil)
        }

        var body: some View {
            NavigationView {
                ZStack {
                    // Background gradient
                    LinearGradient(
                        gradient: Gradient(colors: [Color.bgDarkBlue, Color.bgDarkerDarkBlue]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()

                    VStack(spacing: 0) {
                        if (nonInfoOnboardingSteps + [OnboardingStep.overview, OnboardingStep.completed]).contains(currentStep) {
                            // Progress bar
                            OnboardingProgressBar(
                                currentChapter: currentChapter,
                                currentStep: currentStep,
                                chapterProgress: chapterProgress
                            )
                            .padding(.top)
                        } else {
                            // avoid letting content scroll beneath the status bar / dynamic island for content views with no progress bar (which adds top spacing)
                            Color.clear.frame(height: 1)
                        }

                        OnboardingStepContent(
                            wasMigrationSuccessful: wasMigrationSuccessful,
                            currentStep: $currentStep,
                            showingChapterCompletion: $showingChapterCompletion,
                            currentStartupSubstep: $currentStartupSubstep,
                            currentCloudRestoreSubstep: $currentCloudRestoreSubstep,
                            currentDeliverySubstep: $currentDeliverySubstep,
                            currentAlgorithmSettingsOverviewSubstep: $currentAlgorithmSettingsOverviewSubstep,
                            currentAutosensSubstep: $currentAutosensSubstep,
                            currentSMBSubstep: $currentSMBSubstep,
                            currentTargetBehaviorSubstep: $currentTargetBehaviorSubstep,
                            state: state,
                            navigationDirection: navigationDirection
                        )
                        .disabled(state.restoreInProgress)
                        .overlay { if state.restoreInProgress { ProgressView("Restoring settings…") } }

                        Spacer()

                        OnboardingNavigationButtons(
                            currentStep: $currentStep,
                            showingChapterCompletion: $showingChapterCompletion,
                            currentStartupSubstep: $currentStartupSubstep,
                            currentCloudRestoreSubstep: $currentCloudRestoreSubstep,
                            currentDeliverySubstep: $currentDeliverySubstep,
                            currentAlgorithmSettingsOverviewSubstep: $currentAlgorithmSettingsOverviewSubstep,
                            currentAutosensSubstep: $currentAutosensSubstep,
                            currentSMBSubstep: $currentSMBSubstep,
                            currentTargetBehaviorSubstep: $currentTargetBehaviorSubstep,
                            onboardingManager: onboardingManager,
                            isFreshTrioInstall: state.isFreshTrioInstall,
                            state: state,
                            shouldDisableNextButton: shouldDisableNextButton,
                            navigationDirectionChanged: { navigationDirection = $0 }
                        )
                    }
                }
                .navigationBarHidden(true)
            }
            .onAppear(perform: configureView)
            .alert("Settings Restored!", isPresented: $state.showCloudRestoreSuccess) {
                Button("Done") {
                    currentStep = .targetBehavior
                    currentTargetBehaviorSubstep = .halfBasalTarget
                    showingChapterCompletion = .algorithmSettings
                }
            } message: {
                Text("Trio has been switched to Open Loop.\n\nReview your restored settings before pairing a new insulin pump and returning to Closed Loop.")
            }
            .alert("iCloud Restore Failed", isPresented: Binding(
                get: { state.restoreErrorMessage != nil },
                set: { if !$0 { state.restoreErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(state.restoreErrorMessage ?? "")
            }
        }
    }
}

/// A progress bar that shows the user's progress through the onboarding process.
struct OnboardingProgressBar: View {
    let currentChapter: OnboardingChapter
    let currentStep: OnboardingStep
    let chapterProgress: CGFloat

    private let capsuleSize = CGFloat(UIFont.preferredFont(forTextStyle: .subheadline).pointSize) * 1.3

    private var shouldShowCurrentChapter: Bool {
        currentStep != .overview && currentStep != .completed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // only show this for the actual chapters, not the overview of chapters or completed view
            if shouldShowCurrentChapter {
                HStack(spacing: CGFloat(UIFont.preferredFont(forTextStyle: .subheadline).pointSize)) {
                    Text("\(currentChapter.rawValue + 1)")
                        .font(.subheadline)
                        .fontWeight(.heavy)
                        .frame(width: capsuleSize, height: capsuleSize, alignment: .center)
                        .background(Color.blue)
                        .foregroundStyle(Color.bgDarkBlue)
                        .clipShape(Capsule())
                    Text(currentChapter.title)
                        .font(.subheadline)
                        .kerning(capsuleSize / 4)
                        .textCase(.uppercase)
                        .bold()
                        .foregroundStyle(Color.secondary)
                }
            }

            HStack(spacing: 4) {
                ForEach(OnboardingChapter.allCases, id: \.rawValue) { chapter in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 4)
                            .cornerRadius(2)

                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color.blue)
                                .frame(
                                    width: geo.size.width * chapterFill(chapter),
                                    height: 4
                                )
                                .cornerRadius(2)
                        }
                    }
                    .frame(height: 4)
                }
            }
        }.padding(.horizontal)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(progressAccessibilityLabel))
    }

    private var progressAccessibilityLabel: String {
        let chapterCount = OnboardingChapter.allCases.count
        let chapter = String(
            format: String(localized: "Chapter %1$d of %2$d, %3$@", comment: "Accessibility: onboarding progress"),
            currentChapter.rawValue + 1,
            chapterCount,
            currentChapter.title
        )
        return chapter
    }

    private func chapterFill(_ chapter: OnboardingChapter) -> CGFloat {
        if currentStep == .completed { return 1 }
        if currentStep == .overview { return 0 }
        if chapter.rawValue < currentChapter.rawValue { return 1 }
        guard chapter == currentChapter else { return 0 }
        return min(max(chapterProgress, 0), 1)
    }
}

struct OnboardingStepContent: View {
    var wasMigrationSuccessful: Bool
    @Binding var currentStep: OnboardingStep
    @Binding var showingChapterCompletion: OnboardingChapter?
    @Binding var currentStartupSubstep: StartupSubstep
    @Binding var currentCloudRestoreSubstep: CloudRestoreSubstep
    @Binding var currentDeliverySubstep: DeliveryLimitSubstep
    @Binding var currentAlgorithmSettingsOverviewSubstep: AlgorithmSettingsOverviewSubstep
    @Binding var currentAutosensSubstep: AutosensSettingsSubstep
    @Binding var currentSMBSubstep: SMBSettingsSubstep
    @Binding var currentTargetBehaviorSubstep: TargetBehaviorSubstep
    @Bindable var state: Onboarding.StateModel
    var navigationDirection: OnboardingNavigationDirection
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private var transition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        switch navigationDirection {
        case .forward:
            return .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        case .backward:
            return .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
        }
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    Color.clear.frame(height: 0).id("top")

                    if currentStep != .welcome, currentStep != .completed, showingChapterCompletion == nil {
                        contentHeader
                    }

                    if let chapter = showingChapterCompletion {
                        CompletedStepView(isOnboardingCompleted: false, currentChapter: chapter)
                    } else {
                        Group {
                            switch currentStep {
                            case .welcome:
                                WelcomeStepView()
                            case .startupInfo:
                                switch currentStartupSubstep {
                                case .startupGuide:
                                    StartupGuideStepView(state: state)
                                case .returningUser:
                                    StartupReturningUserStepView(state: state, wasMigrationSuccessful: wasMigrationSuccessful)
                                case .forceCloseWarning:
                                    StartupForceCloseWarningStepView(state: state)
                                }
                            case .overview:
                                OverviewStepView()
                            case .cloudRestore:
                                if currentCloudRestoreSubstep == .choice {
                                    CloudRestoreChoiceStepView(state: state)
                                } else {
                                    TrioCloudBackupBrowser(
                                        onSelectForOnboarding: { state.pendingCloudRestore = $0 },
                                        selectedBackupID: state.pendingCloudRestore?.id.uuidString
                                    )
                                }
                            case .unitSelection:
                                UnitSelectionStepView(state: state)
                            case .glucoseTarget:
                                GlucoseTargetStepView(state: state)
                            case .basalRates:
                                BasalProfileStepView(state: state)
                            case .carbRatio:
                                CarbRatioStepView(state: state)
                            case .insulinSensitivity:
                                InsulinSensitivityStepView(state: state)
                            case .deliveryLimits:
                                DeliveryLimitsStepView(state: state, substep: currentDeliverySubstep)
                            case .algorithmSettings:
                                switch currentAlgorithmSettingsOverviewSubstep {
                                case .contents:
                                    AlgorithmSettingsContentsStepView(state: state)
                                case .importantNotes:
                                    AlgorithmSettingsImportantNotesStepView(state: state)
                                }
                            case .autosensSettings:
                                AlgorithmSettingsSubstepView(state: state, substep: currentAutosensSubstep)
                            case .smbSettings:
                                AlgorithmSettingsSubstepView(state: state, substep: currentSMBSubstep)
                            case .targetBehavior:
                                AlgorithmSettingsSubstepView(state: state, substep: currentTargetBehaviorSubstep)
                            case .notifications:
                                NotificationPermissionStepView(state: state, currentStep: $currentStep)
                            case .bluetooth:
                                BluetoothPermissionStepView(
                                    state: state,
                                    bluetoothManager: state.bluetoothManager,
                                    currentStep: $currentStep
                                )
                            case .completed:
                                CompletedStepView(isOnboardingCompleted: true, currentChapter: nil)
                            }
                        }
                        .transition(transition)
                        .padding(.horizontal)
                        .id(currentStep.id)
                    }
                }
                .padding(.bottom, 80)
            }
            .onChange(of: currentStep) { _, _ in scrollProxy.scrollTo("top", anchor: .top)
                announceScreenChange() }
            .onChange(of: currentStartupSubstep) { _, _ in scrollProxy.scrollTo("top", anchor: .top)
                announceScreenChange() }
            .onChange(of: currentCloudRestoreSubstep) { _, _ in scrollProxy.scrollTo("top", anchor: .top)
                announceScreenChange() }
            .onChange(of: currentDeliverySubstep) { _, _ in scrollProxy.scrollTo("top", anchor: .top)
                announceScreenChange() }
            .onChange(of: currentAlgorithmSettingsOverviewSubstep) { _, _ in scrollProxy.scrollTo("top", anchor: .top)
                announceScreenChange() }
            .onChange(of: currentAutosensSubstep) { _, _ in scrollProxy.scrollTo("top", anchor: .top)
                announceScreenChange() }
            .onChange(of: currentSMBSubstep) { _, _ in scrollProxy.scrollTo("top", anchor: .top)
                announceScreenChange() }
            .onChange(of: currentTargetBehaviorSubstep) { _, _ in scrollProxy.scrollTo("top", anchor: .top)
                announceScreenChange() }
            .safeAreaInset(edge: .top) {
                // avoid letting content scroll beneath the status bar / dynamic island for content views with not progress bar (which adds top spacing)
                if currentStep == .startupInfo || currentStep == .completed {
                    Color.clear.frame(height: 0)
                }
            }
        }
    }

    /// Move VoiceOver focus back to the top of the new step; otherwise focus stays on the
    /// "Next" button and the user must navigate backwards to reach the new content.
    private func announceScreenChange() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }

    private var contentHeader: some View {
        HStack {
            Group {
                if currentStep == .bluetooth {
                    Image(currentStep.iconName)
                        .font(.system(size: 40))
                        .foregroundColor(currentStep.accentColor)
                        .frame(width: 60, height: 60)
                        .background(
                            Circle()
                                .fill(currentStep.accentColor.opacity(0.2))
                        )
                } else {
                    Image(systemName: currentStep.iconName)
                        .font(.system(size: 40, weight: currentStep == .cloudRestore ? .semibold : .regular))
                        .foregroundColor(currentStep.accentColor)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(currentStep.accentColor.opacity(0.2)))
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading) {
                Text(currentStep.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text(currentStep.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct OnboardingNavigationButtons: View {
    @Binding var currentStep: OnboardingStep
    @Binding var showingChapterCompletion: OnboardingChapter?
    @Binding var currentStartupSubstep: StartupSubstep
    @Binding var currentCloudRestoreSubstep: CloudRestoreSubstep
    @Binding var currentDeliverySubstep: DeliveryLimitSubstep
    @Binding var currentAlgorithmSettingsOverviewSubstep: AlgorithmSettingsOverviewSubstep
    @Binding var currentAutosensSubstep: AutosensSettingsSubstep
    @Binding var currentSMBSubstep: SMBSettingsSubstep
    @Binding var currentTargetBehaviorSubstep: TargetBehaviorSubstep

    let onboardingManager: OnboardingManager
    let isFreshTrioInstall: Bool
    @Bindable var state: Onboarding.StateModel
    var shouldDisableNextButton: Bool
    var navigationDirectionChanged: (OnboardingNavigationDirection) -> Void
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        HStack {
            if currentStep != .welcome {
                Button(action: {
                    navigationDirectionChanged(.backward)
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .default) {
                        handleBackNavigation()
                    }
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .padding()
                    .foregroundColor(.primary)
                }
            }

            Spacer()

            Button(action: {
                navigationDirectionChanged(.forward)
                withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .default) {
                    handleNextNavigation()
                }
            }) {
                HStack {
                    Text(currentStep == .completed ? "Get Started" : "Next")
                    Image(systemName: "chevron.right")
                }
                .padding()
                .foregroundColor(.white)
                .background(Capsule().fill(!shouldDisableNextButton ? Color.blue : Color(.systemGray)))
            }
            .disabled(shouldDisableNextButton)
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    // MARK: - Navigation Logic

    private func handleBackNavigation() {
        guard !state.restoreInProgress else { return }
        if let chapter = showingChapterCompletion {
            showingChapterCompletion = nil
            if chapter == .algorithmSettings, state.appliedCloudRestoreID != nil {
                currentStep = .cloudRestore
                currentCloudRestoreSubstep = .choice
            } else if chapter == .importSettings {
                currentCloudRestoreSubstep = .choice
            }
            return
        }

        switch currentStep {
        case .startupInfo:
            var previous = StartupSubstep(rawValue: currentStartupSubstep.rawValue - 1)

            /// Skip `.returningUser` if this is a fresh install
            if previous == .returningUser, isFreshTrioInstall == true {
                previous = StartupSubstep(rawValue: previous!.rawValue - 1)
            }

            if let previousSub = previous {
                currentStartupSubstep = previousSub
            } else if let previous = currentStep.previous {
                currentStep = previous
                currentStartupSubstep = .startupGuide
            }

        case .overview:
            currentStartupSubstep = .forceCloseWarning

            if let previous = currentStep.previous {
                currentStep = previous
            }

        case .cloudRestore:
            if currentCloudRestoreSubstep == .backups { currentCloudRestoreSubstep = .choice }
            else { currentStep = .overview }

        case .unitSelection:
            currentStep = .cloudRestore
            currentCloudRestoreSubstep = .choice
            showingChapterCompletion = .importSettings

        case .deliveryLimits:
            if let previousSub = DeliveryLimitSubstep(rawValue: currentDeliverySubstep.rawValue - 1) {
                currentDeliverySubstep = previousSub
            } else if let previous = currentStep.previous {
                currentStep = previous
                currentDeliverySubstep = .maxIOB
                showingChapterCompletion = .therapySettings
            }

        case .algorithmSettings:
            if let previousSub = AlgorithmSettingsOverviewSubstep(
                rawValue: currentAlgorithmSettingsOverviewSubstep
                    .rawValue - 1
            ) {
                currentAlgorithmSettingsOverviewSubstep = previousSub
            } else if let previous = currentStep.previous {
                currentStep = previous
                currentDeliverySubstep = .minimumSafetyThreshold
                currentAutosensSubstep = .autosensMin
                showingChapterCompletion = .deliveryLimits
            }

        case .autosensSettings:
            let steps = state.filteredAutosensSettingsSubsteps
            if let current = steps.firstIndex(of: currentAutosensSubstep),
               current > 0
            {
                currentAutosensSubstep = steps[current - 1]
            } else if let previousStep = currentStep.previous {
                currentStep = previousStep
                currentAlgorithmSettingsOverviewSubstep = .importantNotes
                currentAutosensSubstep = steps.first ?? .autosensMin
            }

        case .smbSettings:
            currentAlgorithmSettingsOverviewSubstep = .importantNotes

            if let previous = SMBSettingsSubstep(rawValue: currentSMBSubstep.rawValue - 1) {
                /// If user has activated setting `.enableSMBAlways`, when navigating backwards
                /// skip other redundant "Enable SMB"-settings and go straight to `enableSMBAlways`
                /// from current substep `.allowSMBWithHighTempTarget`.
                if state.enableSMBAlways, currentSMBSubstep == .allowSMBWithHighTempTarget {
                    currentSMBSubstep = .enableSMBAlways
                } else {
                    currentSMBSubstep = previous
                }
            } else if let previousStep = currentStep.previous {
                currentStep = previousStep
                currentSMBSubstep = .enableSMBAlways

                currentAutosensSubstep = state.pumpOptionForOnboardingUnits.reportsRewindEvents
                    ? .rewindResetsAutosens
                    : .autosensMax
            }

        case .targetBehavior:
            if let previous = TargetBehaviorSubstep(rawValue: currentTargetBehaviorSubstep.rawValue - 1) {
                currentTargetBehaviorSubstep = previous
            } else if let previousStep = currentStep.previous {
                currentStep = previousStep
                currentTargetBehaviorSubstep = .highTempTargetRaisesSensitivity
                currentSMBSubstep = .maxDeltaGlucoseThreshold
            }

        case .notifications:
            if state.appliedCloudRestoreID != nil {
                currentStep = .targetBehavior
                currentTargetBehaviorSubstep = .halfBasalTarget
                showingChapterCompletion = .algorithmSettings
                return
            }
            currentTargetBehaviorSubstep = .halfBasalTarget

            if let previous = currentStep.previous {
                currentStep = previous
                showingChapterCompletion = .algorithmSettings
            }

        case .completed:
            currentStep = .bluetooth

        default:
            if let previous = currentStep.previous {
                currentStep = previous
            }
        }
    }

    private func handleNextNavigation() {
        guard !state.restoreInProgress else { return }
        if showingChapterCompletion != nil {
            showingChapterCompletion = nil
            if let next = currentStep.next { currentStep = next }
            return
        }

        if let chapter = currentStep.chapterCompletion {
            showingChapterCompletion = chapter
            return
        }

        switch currentStep {
        case .startupInfo:
            let nextSubstepRaw = currentStartupSubstep.rawValue + 1

            if isFreshTrioInstall, StartupSubstep(rawValue: nextSubstepRaw) == .returningUser {
                /// Skip `.returningUser` if it's a fresh install
                if let nextAfterSkip = StartupSubstep(rawValue: nextSubstepRaw + 1) {
                    currentStartupSubstep = nextAfterSkip
                } else if let nextStep = currentStep.next {
                    currentStep = nextStep
                    currentStartupSubstep = .startupGuide
                }
            } else if let next = StartupSubstep(rawValue: nextSubstepRaw) {
                currentStartupSubstep = next
            } else if let nextStep = currentStep.next {
                currentStep = nextStep
                currentStartupSubstep = .startupGuide
            }

        case .cloudRestore:
            if currentCloudRestoreSubstep == .choice {
                if state.cloudRestoreOption == .restore { currentCloudRestoreSubstep = .backups }
                else { showingChapterCompletion = .importSettings }
            } else {
                state.restoreInProgress = true
                Task { @MainActor in
                    defer { state.restoreInProgress = false }
                    do {
                        try await state.applySelectedCloudBackup()
                        state.showCloudRestoreSuccess = true
                    } catch {
                        state.restoreErrorMessage = "Restore stopped. No pump settings were sent.\n\n" + error
                            .localizedDescription }
                }
            }

        case .deliveryLimits:
            if let next = DeliveryLimitSubstep(rawValue: currentDeliverySubstep.rawValue + 1) {
                currentDeliverySubstep = next
            } else {
                /// Setting delivery substep to the last substep (`.minimumSafetyThreshold`) and `showingChapterCompletion` to non-`nil`
                /// prompts display of chapter completion screen; if user navigates back, it stays at correct substep.
                currentDeliverySubstep = .minimumSafetyThreshold
                showingChapterCompletion = .deliveryLimits
            }

        case .algorithmSettings:
            if let next = AlgorithmSettingsOverviewSubstep(rawValue: currentAlgorithmSettingsOverviewSubstep.rawValue + 1) {
                currentAlgorithmSettingsOverviewSubstep = next
            } else if let nextStep = currentStep.next {
                currentStep = nextStep
                currentAlgorithmSettingsOverviewSubstep = .contents
            }

        case .autosensSettings:
            let steps = state.filteredAutosensSettingsSubsteps
            if let current = steps.firstIndex(of: currentAutosensSubstep),
               current + 1 < steps.count
            {
                currentAutosensSubstep = steps[current + 1]
            } else if let nextStep = currentStep.next {
                currentStep = nextStep
                currentAutosensSubstep = steps.first ?? .autosensMin
            }

        case .smbSettings:
            if let next = SMBSettingsSubstep(rawValue: currentSMBSubstep.rawValue + 1) {
                /// If user has activated setting `.enableSMBAlways`, when navigating forward
                /// skip other redundant "Enable SMB"-settings and go straight to `.allowSMBWithHighTempTarget`
                /// from current substep `.enableSMBAlways`.
                if state.enableSMBAlways, currentSMBSubstep == .enableSMBAlways {
                    currentSMBSubstep = .allowSMBWithHighTempTarget
                } else {
                    currentSMBSubstep = next
                }
            } else if let nextStep = currentStep.next {
                currentStep = nextStep
                currentSMBSubstep = .enableSMBAlways
            }

        case .targetBehavior:
            if let next = TargetBehaviorSubstep(rawValue: currentTargetBehaviorSubstep.rawValue + 1) {
                currentTargetBehaviorSubstep = next
            } else {
                /// Setting target behavior substep to the last substep (`.halfBasalTarget`) and `showingChapterCompletion` to non-`nil`
                /// prompts display of chapter completion screen; if user navigates back, it stays at correct substep.
                currentTargetBehaviorSubstep = .halfBasalTarget
                showingChapterCompletion = .algorithmSettings
            }

        case .notifications:
            currentTargetBehaviorSubstep = .halfBasalTarget

            // AlarmKit is the audible channel for critical alarms on iOS 26+
            // builds without the Critical Alerts entitlement — it's what lets
            // them pierce Silent and Focus. No-ops below iOS 26 or once decided.
            Task { await CriticalAlertAlarmScheduler.requestAuthorization() }

            if let next = currentStep.next {
                state.notificationsManager.getNotificationSettings { notificationSettings in
                    switch notificationSettings.authorizationStatus {
                    case .notDetermined:
                        state.notificationsManager.requestNotificationPermissions { granted in
                            state.hasNotificationsGranted = granted
                            currentStep = next
                        }
                    case .denied:
                        state.shouldDisplayCustomNotificationAlert = true
                    case .authorized,
                         .ephemeral,
                         .provisional:
                        currentStep = next
                        break
                    @unknown default:
                        currentStep = next
                    }
                }
            }

        case .bluetooth:
            if let next = currentStep.next {
                if state.bluetoothManager.bluetoothAuthorization != .authorized {
                    state.shouldDisplayBluetoothRequestAlert = true
                } else {
                    currentStep = next
                }
            }

        case .completed:
            if state.pendingCloudRestore != nil {
                guard !state.restoreInProgress else { return }
                state.restoreInProgress = true
                Task { @MainActor in
                    defer { state.restoreInProgress = false }
                    do {
                        try await state.applySelectedCloudBackup()
                        onboardingManager.completeOnboarding()
                        Foundation.NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
                    } catch {
                        state.restoreErrorMessage = "Restore stopped. No pump settings were sent.\n\n" + error
                            .localizedDescription
                    }
                }
            } else {
                state.saveOnboardingData()
                onboardingManager.completeOnboarding()
                Foundation.NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
            }

        default:
            if let next = currentStep.next {
                currentStep = next
            }
        }
    }
}

struct Onboarding_Preview: PreviewProvider {
    static var previews: some View {
        Group {
            let resolver = TrioApp.resolver
            let onboardingManager = OnboardingManager()
            Onboarding.RootView(resolver: resolver, onboardingManager: onboardingManager, wasMigrationSuccessful: true)
                .environment(AppState())
                .previewDisplayName("Onboarding Flow")
        }
    }
}

private struct CloudRestoreChoiceStepView: View {
    @Bindable var state: Onboarding.StateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.bgDarkBlue, Color.blue)
                        .symbolRenderingMode(.palette)
                    Text("Information").foregroundStyle(Color.blue)
                }.bold()

                Text("You can restore settings from an iCloud backup later, even if you choose to start fresh now.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.chart.opacity(0.65))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue, lineWidth: 2))
            .cornerRadius(10)

            VStack(spacing: 0) {
                choice("Restore Settings From iCloud", option: .restore)
                Divider().padding(.horizontal)
                choice("Start Fresh With New Settings", option: .startFresh)
            }
            .background(Color.chart.opacity(0.65))
            .cornerRadius(10)
        }
    }

    private func choice(_ title: String, option: CloudRestoreOption) -> some View {
        Button { state.chooseCloudRestoreOption(option) } label: {
            HStack {
                Text(title).foregroundStyle(Color.white)
                Spacer()
                if state.cloudRestoreOption == option {
                    Image(systemName: "checkmark").foregroundStyle(Color.blue).fontWeight(.semibold)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(state.cloudRestoreOption == option ? [.isSelected] : [])
    }
}
