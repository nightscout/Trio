import Foundation
import SwiftUI
import Swinject

/// The main onboarding view that manages navigation between onboarding steps.
extension Onboarding {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State private var navigationDirection: OnboardingNavigationDirection = .forward
        let onboardingManager: OnboardingManager
        let wasMigrationSuccessful: Bool

        // Step management
        @State private var currentChapter: OnboardingChapter = .prepareTrio
        @State private var showingChapterCompletion: OnboardingChapter? = nil

        @State private var currentStep: OnboardingStep = .welcome
        @State private var currentStartupSubstep: StartupSubstep = .startupGuide
        @State private var currentNightscoutSubstep: NightscoutSubstep = .setupSelection
        @State private var currentDeliverySubstep: DeliveryLimitSubstep = .maxIOB
        @State private var currentAlgorithmSettingsOverviewSubstep: AlgorithmSettingsOverviewSubstep = .contents
        @State private var currentAutosensSubstep: AutosensSettingsSubstep = .autosensMin
        @State private var currentSMBSubstep: SMBSettingsSubstep = .enableSMBAlways
        @State private var currentTargetBehaviorSubstep: TargetBehaviorSubstep = .highTempTargetRaisesSensitivity

        private func updateCurrentChapter() {
            switch currentStep {
            case .diagnostics,
                 .nightscout,
                 .unitSelection:
                currentChapter = .prepareTrio
            case .basalRates,
                 .carbRatio,
                 .glucoseTarget,
                 .insulinSensitivity:
                currentChapter = .therapySettings
            case .deliveryLimits:
                currentChapter = .deliveryLimits
            case .algorithmSettings,
                 .autosensSettings,
                 .smbSettings,
                 .targetBehavior:
                currentChapter = .algorithmSettings
            case .bluetooth,
                 .notifications:
                currentChapter = .permissionRequests
            default:
                break
            }
        }

        // Animation states
        @State private var animationScale: CGFloat = 1.0
        @State private var animationOpacity: Double = 0
        @State private var isAnimating = false

        // Conditional button states for Nightscout substeps
        private var didSelectNightscoutSetupOption: Bool {
            currentNightscoutSubstep == .setupSelection && state
                .nightscoutSetupOption == .noSelection
        }

        private var hasValidNightscoutConnection: Bool {
            currentNightscoutSubstep == .connectToNightscout && !state.isConnectedToNS
        }

        private var didSelectNightscoutImportOption: Bool {
            currentNightscoutSubstep == .importFromNightscout && state.nightscoutImportOption == .noSelection
        }

        // Next button conditional
        private var shouldDisableNextButton: Bool {
            (currentStep == .diagnostics && state.diagnosticsSharingOption == .enabled && !state.hasAcceptedPrivacyPolicy)
                ||
                (currentStep == .nightscout && didSelectNightscoutSetupOption)
                ||
                (currentStep == .nightscout && hasValidNightscoutConnection)
                ||
                (currentStep == .nightscout && didSelectNightscoutImportOption)
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
                                shouldDisplayChapterTitle: showingChapterCompletion == nil,
                                currentStep: currentStep,
                                currentSubstep: {
                                    switch currentStep {
                                    case .deliveryLimits: return currentDeliverySubstep.rawValue
                                    case .nightscout: return currentNightscoutSubstep.rawValue
                                    case .algorithmSettings: return currentAlgorithmSettingsOverviewSubstep.rawValue
                                    case .autosensSettings: return currentAutosensSubstep.rawValue
                                    case .smbSettings: return currentSMBSubstep.rawValue
                                    case .targetBehavior: return currentTargetBehaviorSubstep.rawValue
                                    default: return nil
                                    }
                                }(),
                                stepsWithSubsteps: [
                                    .nightscout: NightscoutSubstep.allCases.count,
                                    .deliveryLimits: DeliveryLimitSubstep.allCases.count,
                                    .algorithmSettings: AlgorithmSettingsOverviewSubstep.allCases.count,
                                    .autosensSettings: state.filteredAutosensSettingsSubsteps.count,
                                    .smbSettings: SMBSettingsSubstep.allCases.count,
                                    .targetBehavior: TargetBehaviorSubstep.allCases.count
                                ],
                                nightscoutSetupOption: state.nightscoutSetupOption
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
                            currentNightscoutSubstep: $currentNightscoutSubstep,
                            currentDeliverySubstep: $currentDeliverySubstep,
                            currentAlgorithmSettingsOverviewSubstep: $currentAlgorithmSettingsOverviewSubstep,
                            currentAutosensSubstep: $currentAutosensSubstep,
                            currentSMBSubstep: $currentSMBSubstep,
                            currentTargetBehaviorSubstep: $currentTargetBehaviorSubstep,
                            state: state,
                            navigationDirection: navigationDirection
                        )

                        Spacer()

                        OnboardingNavigationButtons(
                            currentStep: $currentStep,
                            showingChapterCompletion: $showingChapterCompletion,
                            currentStartupSubstep: $currentStartupSubstep,
                            currentNightscoutSubstep: $currentNightscoutSubstep,
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
            .onChange(of: currentStep) { _, _ in
                // Reset animation when step changes
                animationScale = 0.9
                animationOpacity = 0
                isAnimating = false

                // Start new animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.7)) {
                        animationOpacity = 1
                        animationScale = 1.0
                    }
                    isAnimating = true
                }

                updateCurrentChapter()
            }
            .onAppear(perform: configureView)
        }
    }
}

/// A progress bar that shows the user's progress through the onboarding process.
struct OnboardingProgressBar: View {
    let currentChapter: OnboardingChapter
    let shouldDisplayChapterTitle: Bool
    let currentStep: OnboardingStep
    let currentSubstep: Int?
    let stepsWithSubsteps: [OnboardingStep: Int]
    let nightscoutSetupOption: NightscoutSetupOption

    private let capsuleSize = CGFloat(UIFont.preferredFont(forTextStyle: .subheadline).pointSize) * 1.3

    private var shouldShowCurrentChapter: Bool {
        shouldDisplayChapterTitle && currentStep != .overview && currentStep != .completed
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
                ForEach(renderedSteps, id: \.id) { step in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 4)
                            .cornerRadius(2)

                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color.blue)
                                .frame(
                                    width: geo.size.width * fillFraction(for: step.step, totalSubsteps: step.substeps),
                                    height: 4
                                )
                                .cornerRadius(2)
                        }
                    }
                    .frame(height: 4)
                }
            }
        }.padding(.horizontal)
    }

    private var renderedSteps: [(id: String, step: OnboardingStep, substeps: Int?)] {
        nonInfoOnboardingSteps.map {
            (id: "\($0.rawValue)", step: $0, substeps: stepsWithSubsteps[$0])
        }
    }

    private func fillFraction(for step: OnboardingStep, totalSubsteps: Int?) -> CGFloat {
        // If currentStep is .completed, fill everything
        if currentStep == .completed { return 1.0 }

        if let currentIndex = nonInfoOnboardingSteps.firstIndex(of: currentStep),
           let stepIndex = nonInfoOnboardingSteps.firstIndex(of: step),
           stepIndex < currentIndex
        {
            return 1.0
        }

        if step == currentStep {
            if let total = totalSubsteps, let current = currentSubstep {
                return CGFloat(current + 1) / CGFloat(total)
            } else {
                return 1.0
            }
        }

        // Handle special case: Nightscout was skipped
        if step == .nightscout,
           nightscoutSetupOption == .skipNightscoutSetup,
           let currentIndex = nonInfoOnboardingSteps.firstIndex(of: currentStep),
           let nightscoutIndex = nonInfoOnboardingSteps.firstIndex(of: .nightscout),
           currentIndex > nightscoutIndex
        {
            return 1.0
        }

        return 0.0
    }
}

struct OnboardingStepContent: View {
    var wasMigrationSuccessful: Bool
    @Binding var currentStep: OnboardingStep
    @Binding var showingChapterCompletion: OnboardingChapter?
    @Binding var currentStartupSubstep: StartupSubstep
    @Binding var currentNightscoutSubstep: NightscoutSubstep
    @Binding var currentDeliverySubstep: DeliveryLimitSubstep
    @Binding var currentAlgorithmSettingsOverviewSubstep: AlgorithmSettingsOverviewSubstep
    @Binding var currentAutosensSubstep: AutosensSettingsSubstep
    @Binding var currentSMBSubstep: SMBSettingsSubstep
    @Binding var currentTargetBehaviorSubstep: TargetBehaviorSubstep
    @Bindable var state: Onboarding.StateModel
    var navigationDirection: OnboardingNavigationDirection

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
                            case .diagnostics:
                                DiagnosticsStepView(state: state)
                            case .nightscout:
                                switch currentNightscoutSubstep {
                                case .setupSelection:
                                    NightscoutSetupStepView(state: state)
                                case .connectToNightscout:
                                    NightscoutLoginStepView(state: state)
                                case .importFromNightscout:
                                    NightscoutImportStepView(state: state)
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
                        .transition(
                            navigationDirection == .forward
                                ? .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
                                : .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
                        )
                        .padding(.horizontal)
                        .id(currentStep.id)
                    }
                }
                .padding(.bottom, 80)
            }
            .onChange(of: currentStep) { _, _ in scrollProxy.scrollTo("top", anchor: .top) }
            .onChange(of: currentStartupSubstep) { _, _ in scrollProxy.scrollTo("top", anchor: .top) }
            .onChange(of: currentNightscoutSubstep) { _, _ in scrollProxy.scrollTo("top", anchor: .top) }
            .onChange(of: currentDeliverySubstep) { _, _ in scrollProxy.scrollTo("top", anchor: .top) }
            .onChange(of: currentAlgorithmSettingsOverviewSubstep) { _, _ in scrollProxy.scrollTo("top", anchor: .top) }
            .onChange(of: currentAutosensSubstep) { _, _ in scrollProxy.scrollTo("top", anchor: .top) }
            .onChange(of: currentSMBSubstep) { _, _ in scrollProxy.scrollTo("top", anchor: .top) }
            .onChange(of: currentTargetBehaviorSubstep) { _, _ in scrollProxy.scrollTo("top", anchor: .top) }
            .safeAreaInset(edge: .top) {
                // avoid letting content scroll beneath the status bar / dynamic island for content views with not progress bar (which adds top spacing)
                if currentStep == .startupInfo || currentStep == .completed {
                    Color.clear.frame(height: 0)
                }
            }
        }
    }

    private var contentHeader: some View {
        HStack {
            if currentStep == .nightscout {
                Image(currentStep.iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
            } else if currentStep == .bluetooth {
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
                    .font(.system(size: 40))
                    .foregroundColor(currentStep.accentColor)
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(currentStep.accentColor.opacity(0.2))
                    )
            }

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
    }
}

struct OnboardingNavigationButtons: View {
    @Binding var currentStep: OnboardingStep
    @Binding var showingChapterCompletion: OnboardingChapter?
    @Binding var currentStartupSubstep: StartupSubstep
    @Binding var currentNightscoutSubstep: NightscoutSubstep
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

    var body: some View {
        HStack {
            if currentStep != .welcome {
                Button(action: {
                    navigationDirectionChanged(.backward)
                    withAnimation {
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
                withAnimation {
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
        if showingChapterCompletion != nil {
            showingChapterCompletion = nil
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

        case .nightscout:
            if currentNightscoutSubstep == .setupSelection,
               let previous = currentStep.previous
            {
                currentStep = previous
                currentNightscoutSubstep = .setupSelection
            } else {
                currentNightscoutSubstep = NightscoutSubstep(rawValue: currentNightscoutSubstep.rawValue - 1)!
            }

        case .deliveryLimits:
            if let previousSub = DeliveryLimitSubstep(rawValue: currentDeliverySubstep.rawValue - 1) {
                currentDeliverySubstep = previousSub
            } else if let previous = currentStep.previous {
                currentStep = previous
                currentDeliverySubstep = .maxIOB
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
            }

        case .autosensSettings:
            let steps = state.filteredAutosensSettingsSubsteps
            if let current = steps.firstIndex(of: currentAutosensSubstep),
               current > 0
            {
                currentAutosensSubstep = steps[current - 1]
            } else if let previousStep = currentStep.previous {
                currentStep = previousStep
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

                switch state.pumpOptionForOnboardingUnits {
                case .dana,
                     .minimed:
                    currentAutosensSubstep = .rewindResetsAutosens
                case .omnipodDash,
                     .omnipodEros:
                    currentAutosensSubstep = .autosensMax
                }
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
            currentTargetBehaviorSubstep = .halfBasalTarget

            if let previous = currentStep.previous {
                currentStep = previous
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
        if showingChapterCompletion != nil {
            showingChapterCompletion = nil
            if let next = currentStep.next {
                currentStep = next
            }
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

        case .nightscout:
            if currentNightscoutSubstep != .importFromNightscout {
                if currentNightscoutSubstep == .setupSelection,
                   state.nightscoutSetupOption == .skipNightscoutSetup,
                   let next = currentStep.next
                {
                    currentStep = next
                } else {
                    currentNightscoutSubstep = NightscoutSubstep(rawValue: currentNightscoutSubstep.rawValue + 1)!
                }
            } else if currentNightscoutSubstep == .importFromNightscout,
                      state.nightscoutImportOption == .useImport
            {
                Task {
                    await state.importSettingsFromNightscout(currentStep: $currentStep)
                }
            } else if let next = currentStep.next {
                currentStep = next
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
            state.saveOnboardingData()
            onboardingManager.completeOnboarding()
            Foundation.NotificationCenter.default.post(name: .onboardingCompleted, object: nil)

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
                .previewDisplayName("Onboarding Flow")
        }
    }
}
