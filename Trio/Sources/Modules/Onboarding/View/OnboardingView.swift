import SwiftUI
import Swinject

/// The main onboarding view that manages navigation between onboarding steps.
extension Onboarding {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        let onboardingManager: OnboardingManager
        @State private var currentStep: OnboardingStep = .welcome
        @State private var currentDeliverySubstep: DeliveryLimitSubstep = .maxIOB

        // Animation states
        @State private var animationScale: CGFloat = 1.0
        @State private var animationOpacity: Double = 0
        @State private var isAnimating = false

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
                        // Progress bar
                        OnboardingProgressBar(
                            currentStep: currentStep,
                            currentSubstep: currentStep == .deliveryLimits ? currentDeliverySubstep.rawValue : nil,
                            stepsWithSubsteps: [.deliveryLimits: DeliveryLimitSubstep.allCases.count]
                        )

                        .padding(.top)

                        // Step content
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                // Header
                                if currentStep != .welcome && currentStep != .completed {
                                    HStack {
                                        Image(systemName: currentStep.iconName)
                                            .font(.system(size: 40))
                                            .foregroundColor(currentStep.accentColor)
                                            .frame(width: 60, height: 60)
                                            .background(
                                                Circle()
                                                    .fill(currentStep.accentColor.opacity(0.2))
                                            )

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

                                // Animation container (for steps that include animations)
//                                AnimationPlaceholder(for: currentStep)
//                                    .padding()
//                                    .scaleEffect(animationScale)
//                                    .opacity(animationOpacity)
//                                    .onAppear {
//                                        withAnimation(.easeInOut(duration: 0.7)) {
//                                            animationOpacity = 1
//                                            animationScale = 1.0
//                                        }
//                                        // Start pulse animation
//                                        isAnimating = true
//                                    }

                                // Step-specific content
                                Group {
                                    switch currentStep {
                                    case .welcome:
                                        WelcomeStepView()
                                    case .unitSelection:
                                        UnitSelectionStepView(state: state)
                                    case .glucoseTarget:
                                        GlucoseTargetStepView(state: state)
                                    case .basalProfile:
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
                                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                                .padding(.horizontal)
                                .id(currentStep.id) // Force view recreation when step changes
                            }
                            .padding(.bottom, 80) // Make room for buttons at bottom
                        }

                        Spacer()

                        // Navigation buttons
                        HStack {
                            // Back button
                            if currentStep != .welcome {
                                Button(action: {
                                    withAnimation {
                                        if currentStep == .completed {
                                            currentStep = .deliveryLimits
                                            currentDeliverySubstep = .maxCOB // ensure we land on the last substep visually
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
                                withAnimation {
                                    if currentStep == .completed {
                                        state.saveOnboardingData()
                                        onboardingManager.completeOnboarding()
                                        Foundation.NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
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
                                .background(Capsule().fill(Color.blue))
                            }
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
    let stepsWithSubsteps: [OnboardingStep: Int] // e.g. [.deliveryLimits: 4]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(renderedSteps, id: \.self.id) { element in
                if let substeps = element.substeps {
                    HStack(spacing: 2) {
                        ForEach(0 ..< substeps, id: \.self) { i in
                            Rectangle()
                                .fill(isSubstepActive(for: element.step, index: i) ? Color.blue : Color.gray.opacity(0.3))
                                .frame(height: 4)
                                .cornerRadius(2)
                        }
                    }
                } else {
                    Rectangle()
                        .fill(isStepActive(element.step) ? Color.blue : Color.gray.opacity(0.3))
                        .frame(height: 4)
                        .cornerRadius(2)
                }
            }
        }
        .padding(.horizontal)
    }

    // Filter only the visible steps (exclude welcome and completed)
    private var visibleSteps: [OnboardingStep] {
        OnboardingStep.allCases.filter { $0 != .welcome && $0 != .completed }
    }

    // Combine steps with info on whether they have substeps
    private var renderedSteps: [(id: String, step: OnboardingStep, substeps: Int?)] {
        visibleSteps.map {
            let sub = stepsWithSubsteps[$0]
            return (id: "\($0.id)", step: $0, substeps: sub)
        }
    }

    private func isStepActive(_ step: OnboardingStep) -> Bool {
        // If we’re at .completed, everything should be filled
        if currentStep == .completed { return true }

        // Current step should be filled
        if step == currentStep { return true }

        // Steps before the current one should be filled
        if let currentIndex = visibleSteps.firstIndex(of: currentStep),
           let stepIndex = visibleSteps.firstIndex(of: step),
           stepIndex < currentIndex
        {
            return true
        }

        return false
    }

    private func isSubstepActive(for step: OnboardingStep, index: Int) -> Bool {
        guard let current = currentSubstep else {
            // Special case: if currentStep is `.completed`, show all substeps as filled
            if currentStep == .completed && step == .deliveryLimits {
                return true
            }
            return false
        }

        if step == currentStep {
            return index <= current
        }

        // If step comes before currentStep, mark all substeps filled
        if let currentIndex = visibleSteps.firstIndex(of: currentStep),
           let stepIndex = visibleSteps.firstIndex(of: step),
           stepIndex < currentIndex
        {
            return true
        }

        return false
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
