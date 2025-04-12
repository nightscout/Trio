import SwiftUI
import Swinject

/// The main onboarding view that manages navigation between onboarding steps.
extension Onboarding {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State private var navigationDirection: OnboardingNavigationDirection = .forward
        let onboardingManager: OnboardingManager
        @State private var currentStep: OnboardingStep = .welcome
        @State private var currentDeliverySubstep: DeliveryLimitSubstep = .maxIOB
        @State private var currentNightscoutSubstep: NightscoutSubstep = .setupSelection

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

        private var shouldDisableNextButton: Bool {
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
                                currentStep: currentStep,
                                currentSubstep: {
                                    switch currentStep {
                                    case .deliveryLimits: return currentDeliverySubstep.rawValue
                                    case .nightscout: return currentNightscoutSubstep.rawValue
                                    default: return nil
                                    }
                                }(),
                                stepsWithSubsteps: [
                                    .nightscout: NightscoutSubstep.allCases.count,
                                    .deliveryLimits: DeliveryLimitSubstep.allCases.count
                                ],
                                nightscoutSetupOption: state.nightscoutSetupOption
                            )
                            .padding(.top)
                        }

                        // Step content
                        ScrollViewReader { scrollProxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 20) {
                                    // Scroll position marker at top
                                    Color.clear.frame(height: 0).id("top")

                                    // Header
                                    if currentStep != .welcome && currentStep != .completed {
                                        HStack {
                                            if currentStep == .nightscout {
                                                Image(currentStep.iconName)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 60, height: 60)

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
                                                    .font(.largeTitle)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.primary)

                                                Text(currentStep.description)
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                        .padding([.horizontal, .top])
                                    }
                                    
                                    // Step-specific content
                                    Group {
                                        switch currentStep {
                                        case .welcome:
                                            WelcomeStepView()
                                        case .startupGuide:
                                            StartupGuideStepView()
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
                                        case .completed:
                                            CompletedStepView()
                                        }
                                    }
                                    .transition(
                                        navigationDirection == .forward
                                            ? .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
                                            : .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
                                    )
                                    .padding(.horizontal)
                                    .id(currentStep.id) // Force view recreation when step changes
                                }
                                .padding(.bottom, 80) // Make room for buttons at bottom
                            }
                            .onChange(of: currentStep) { _, _ in
                                scrollProxy.scrollTo("top", anchor: .top)
                            }
                            .onChange(of: currentNightscoutSubstep) { _, _ in
                                scrollProxy.scrollTo("top", anchor: .top)
                            }
                            .onChange(of: currentDeliverySubstep) { _, _ in
                                scrollProxy.scrollTo("top", anchor: .top)
                            }
                        }

                        Spacer()

                        // Navigation buttons
                        HStack {
                            // Back button
                            if currentStep != .welcome {
                                Button(action: {
                                    navigationDirection = .backward
                                    withAnimation {
                                        if currentStep == .completed {
                                            currentStep = .deliveryLimits
                                            currentDeliverySubstep =
                                                .minimumSafetyThreshold // ensure we land on the last substep visually
                                        } else if currentStep == .nightscout {
                                            if currentNightscoutSubstep == .setupSelection {
                                                // First substep: go to previous main step
                                                if let previousMainStep = currentStep.previous {
                                                    currentStep = previousMainStep
                                                    currentNightscoutSubstep = .setupSelection // reset substep
                                                }
                                            } else {
                                                // Go back one substep
                                                currentNightscoutSubstep = NightscoutSubstep(
                                                    rawValue: currentNightscoutSubstep
                                                        .rawValue - 1
                                                )!
                                            }
                                        } else if currentStep == .deliveryLimits {
                                            if let previousSub = DeliveryLimitSubstep(
                                                rawValue: currentDeliverySubstep
                                                    .rawValue - 1
                                            ) {
                                                currentDeliverySubstep = previousSub
                                            } else if let previousMainStep = currentStep.previous {
                                                currentStep = previousMainStep
                                                currentDeliverySubstep = .maxIOB // reset to first substep for later return
                                            }
                                        } else if let previous = currentStep.previous {
                                            currentStep = previous
                                        }
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

                            // Next/Finish button
                            Button(action: {
                                navigationDirection = .forward
                                withAnimation {
                                    if currentStep == .completed {
                                        state.saveOnboardingData()
                                        onboardingManager.completeOnboarding()
                                        Foundation.NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
                                    } else if currentStep == .nightscout {
                                        if currentNightscoutSubstep != .importFromNightscout {
                                            // Handle conditional skip
                                            if currentNightscoutSubstep == .setupSelection,
                                               state.nightscoutSetupOption == .skipNightscoutSetup,
                                               let next = currentStep.next
                                            {
                                                currentStep = next
                                            } else {
                                                currentNightscoutSubstep = NightscoutSubstep(
                                                    rawValue: currentNightscoutSubstep
                                                        .rawValue + 1
                                                )!
                                            }
                                        } else if currentNightscoutSubstep == .importFromNightscout,
                                                  state.nightscoutImportOption == .useImport
                                        {
                                            // TODO: trigger import, show animation, then proceed to next step
                                            Task {
                                                await state.importSettingsFromNightscout(currentStep: $currentStep)
                                            }
                                        } else if let next = currentStep.next {
                                            currentStep = next
                                        }
                                    } else if currentStep == .deliveryLimits {
                                        if let nextSub = DeliveryLimitSubstep(rawValue: currentDeliverySubstep.rawValue + 1) {
                                            currentDeliverySubstep = nextSub
                                        } else if let next = currentStep.next {
                                            currentStep = next
                                            currentDeliverySubstep = .maxIOB
                                        }
                                    } else if let next = currentStep.next {
                                        currentStep = next
                                    }
                                }
                            }) {
                                HStack {
                                    Text(currentStep == .completed ? "Get Started" : "Next")
                                    Image(systemName: "chevron.right")
                                }
                                .padding()
                                .foregroundColor(.white)
                                .background(Capsule().fill(!shouldDisableNextButton ? Color.blue : Color(.systemGray)))
                            }.disabled(shouldDisableNextButton)
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
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
            }
            .onAppear(perform: configureView)
        }
    }
}

/// A progress bar that shows the user's progress through the onboarding process.
struct OnboardingProgressBar: View {
    let currentStep: OnboardingStep
    let currentSubstep: Int?
    let stepsWithSubsteps: [OnboardingStep: Int]
    let nightscoutSetupOption: NightscoutSetupOption

    var body: some View {
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
        .padding(.horizontal)
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

struct Onboarding_Preview: PreviewProvider {
    static var previews: some View {
        Group {
            let resolver = TrioApp.resolver
            let onboardingManager = OnboardingManager()
            Onboarding.RootView(resolver: resolver, onboardingManager: onboardingManager)
                .previewDisplayName("Onboarding Flow")
        }
    }
}
