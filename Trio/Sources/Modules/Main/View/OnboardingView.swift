import SwiftUI

/// The main onboarding view that manages navigation between onboarding steps.
struct OnboardingView: View {
    let manager: OnboardingManager
    @State private var onboardingData = OnboardingData()
    @State private var currentStep: OnboardingStep = .welcome

    // Animation states
    @State private var animationScale: CGFloat = 1.0
    @State private var animationOpacity: Double = 0
    @State private var isAnimating = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color(UIColor.systemBackground), currentStep.accentColor.opacity(0.1)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Progress bar
                    OnboardingProgressBar(
                        currentStep: OnboardingStep.allCases.firstIndex(of: currentStep) ?? 0,
                        totalSteps: OnboardingStep.allCases.count - 1
                    )
                    .padding(.top)

                    // Step content
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Header
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
                            .padding(.horizontal)
                            .padding(.top)

                            // Animation container (for steps that include animations)
                            AnimationPlaceholder(for: currentStep)
                                .padding()
                                .scaleEffect(animationScale)
                                .opacity(animationOpacity)
                                .onAppear {
                                    withAnimation(.easeInOut(duration: 0.7)) {
                                        animationOpacity = 1
                                        animationScale = 1.0
                                    }
                                    // Start pulse animation
                                    isAnimating = true
                                }

                            // Step-specific content
                            Group {
                                switch currentStep {
                                case .welcome:
                                    WelcomeStepView()
                                case .glucoseTarget:
                                    GlucoseTargetStepView(onboardingData: onboardingData)
                                case .basalProfile:
                                    BasalProfileStepView(onboardingData: onboardingData)
                                case .carbRatio:
                                    CarbRatioStepView(onboardingData: onboardingData)
                                case .insulinSensitivity:
                                    InsulinSensitivityStepView(onboardingData: onboardingData)
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
                                    if let previous = currentStep.previous {
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
                                    // Apply settings and complete onboarding
//                                    onboardingData.applyToSettings(settingsManager: manager.settingsManager)
                                    manager.completeOnboarding()
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
                            .background(
                                Capsule()
                                    .fill(currentStep.accentColor)
                            )
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
    }
}

/// A progress bar that shows the user's progress through the onboarding process.
struct OnboardingProgressBar: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< totalSteps, id: \.self) { step in
                Rectangle()
                    .fill(step <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                    .frame(height: 4)
                    .cornerRadius(2)
            }
        }
        .padding(.horizontal)
    }
}

/// A simple animated placeholder for each step
struct AnimationPlaceholder: View {
    let step: OnboardingStep
    @State private var animationValue: Double = 0

    init(for step: OnboardingStep) {
        self.step = step
    }

    var body: some View {
        VStack {
            Group {
                switch step {
                case .welcome:
                    welcomeAnimation
                case .glucoseTarget:
                    glucoseTargetAnimation
                case .basalProfile:
                    basalProfileAnimation
                case .carbRatio:
                    carbRatioAnimation
                case .insulinSensitivity:
                    insulinSensitivityAnimation
                case .completed:
                    completedAnimation
                }
            }
            .frame(height: 180)
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                animationValue = 1.0
            }
        }
    }

    // Custom animated views for each step
    var welcomeAnimation: some View {
        ZStack {
            ForEach(0 ..< 5) { index in
                Image(systemName: "heart.fill")
                    .font(.system(size: 40))
                    .foregroundColor(step.accentColor.opacity(0.8 - Double(index) * 0.15))
                    .offset(x: CGFloat.random(in: -100 ... 100), y: CGFloat.random(in: -60 ... 60))
                    .scaleEffect(1.0 + animationValue * 0.3)
                    .rotationEffect(.degrees(animationValue * Double.random(in: -30 ... 30)))
            }

            Image(systemName: "syringe.fill")
                .font(.system(size: 80))
                .foregroundColor(step.accentColor)
                .scaleEffect(1.0 + animationValue * 0.2)
                .shadow(color: step.accentColor.opacity(0.5), radius: 10 * animationValue, x: 0, y: 0)
        }
    }

    var glucoseTargetAnimation: some View {
        ZStack {
            // Target rings
            ForEach(0 ..< 3) { index in
                Circle()
                    .stroke(step.accentColor.opacity(Double(3 - index) * 0.3), lineWidth: 8)
                    .frame(width: 120 + CGFloat(index * 40))
                    .scaleEffect(1.0 + animationValue * 0.05)
            }

            // Arrow
            Image(systemName: "arrow.down.to.line")
                .font(.system(size: 50))
                .foregroundColor(step.accentColor)
                .offset(y: -10 + animationValue * 20)
                .rotationEffect(.degrees(animationValue * 360))
        }
    }

    var basalProfileAnimation: some View {
        ZStack {
            // Line graph representation
            Path { path in
                let width: CGFloat = 300
                let height: CGFloat = 100

                path.move(to: CGPoint(x: 0, y: height * 0.5))

                for i in 0 ..< 8 {
                    let x = width * CGFloat(i) / 7
                    let y = height * (0.5 + (sin(Double(i) * .pi / 3) * 0.4))

                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .trim(from: 0, to: animationValue)
            .stroke(step.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            .frame(width: 300, height: 100)

            // Clock symbols to represent time
            HStack(spacing: 50) {
                Image(systemName: "clock")
                    .font(.system(size: 20))
                    .foregroundColor(step.accentColor)
                    .opacity(animationValue)

                Image(systemName: "clock.fill")
                    .font(.system(size: 20))
                    .foregroundColor(step.accentColor)
                    .opacity(animationValue)

                Image(systemName: "clock")
                    .font(.system(size: 20))
                    .foregroundColor(step.accentColor)
                    .opacity(animationValue)
            }
            .offset(y: 70)
        }
    }

    var carbRatioAnimation: some View {
        ZStack {
            // Plate
            Circle()
                .fill(Color.gray.opacity(0.1))
                .frame(width: 150)

            // Food items
            ForEach(0 ..< 5) { index in
                Image(systemName: [
                    "carrot.fill",
                    "fork.knife",
                    "takeoutbag.and.cup.and.straw.fill",
                    "wallet.pass.fill",
                    "cup.and.saucer.fill"
                ][index % 5])
                    .font(.system(size: 25))
                    .foregroundColor(step.accentColor)
                    .offset(
                        x: cos(Double(index) * .pi * 2 / 5) * 50 * animationValue,
                        y: sin(Double(index) * .pi * 2 / 5) * 50 * animationValue
                    )
                    .rotationEffect(.degrees(animationValue * 360))
            }

            // Insulin
            Image(systemName: "drop.fill")
                .font(.system(size: 40))
                .foregroundColor(.blue)
                .scaleEffect(0.8 + animationValue * 0.3)
                .shadow(color: .blue.opacity(0.5), radius: 5, x: 0, y: 0)
        }
    }

    var insulinSensitivityAnimation: some View {
        ZStack {
            // Glucose meter
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.1))
                .frame(width: 120, height: 200)

            // Display screen
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.1))
                .frame(width: 100, height: 60)
                .offset(y: -60)

            // Value on screen
            Text("120")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(step.accentColor)
                .offset(y: -60)
                .opacity(animationValue)

            // Insulin drop
            Image(systemName: "drop.fill")
                .font(.system(size: 30))
                .foregroundColor(.blue)
                .offset(y: 20)
                .opacity(1)

            // Arrow showing decrease
            Image(systemName: "arrow.down")
                .font(.system(size: 30))
                .foregroundColor(step.accentColor)
                .offset(y: 60)
                .opacity(animationValue)
                .scaleEffect(1.0 + animationValue * 0.5)

            // Lower value
            Text("80")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(step.accentColor)
                .offset(y: 100)
                .opacity(animationValue)
        }
    }

    var completedAnimation: some View {
        ZStack {
            // Success checkmark
            Circle()
                .fill(step.accentColor.opacity(0.2))
                .frame(width: 150)
                .scaleEffect(animationValue)

            Circle()
                .stroke(step.accentColor, lineWidth: 5)
                .frame(width: 150)
                .scaleEffect(animationValue)

            Image(systemName: "checkmark")
                .font(.system(size: 80, weight: .bold))
                .foregroundColor(step.accentColor)
                .offset(y: animationValue * 5)
                .scaleEffect(animationValue)

            // Celebrate particles
            ForEach(0 ..< 8) { index in
                Image(systemName: "star.fill")
                    .font(.system(size: 20))
                    .foregroundColor(step.accentColor)
                    .offset(
                        x: cos(Double(index) * .pi / 4) * 100 * animationValue,
                        y: sin(Double(index) * .pi / 4) * 100 * animationValue
                    )
                    .opacity(animationValue)
                    .scaleEffect(animationValue)
            }
        }
    }
}
