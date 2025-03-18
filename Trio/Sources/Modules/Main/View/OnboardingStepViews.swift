import SwiftUI

/// Welcome step view shown at the beginning of onboarding.
struct WelcomeStepView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Text("Welcome to Trio!")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(
                "Trio is designed to help manage your diabetes efficiently. To get the most out of the app, we'll guide you through setting up some essential parameters."
            )
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)

            Text("Let's go through a few quick steps to ensure Trio works optimally for you.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Image("trio-logo")
                .resizable()
                .scaledToFit()
                .frame(height: 100)
                .padding()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

/// Glucose target step view for setting target glucose range.
struct GlucoseTargetStepView: View {
    @State var onboardingData: OnboardingData
    @State private var showUnitPicker = false

    // Formatter for glucose values
    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = onboardingData.units == .mmolL ? 1 : 0
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Unit selector
            HStack {
                Text("Blood Glucose Units")
                    .font(.headline)

                Spacer()

                Button(action: {
                    showUnitPicker.toggle()
                }) {
                    HStack {
                        Text(onboardingData.units == .mgdL ? "mg/dL" : "mmol/L")
                        Image(systemName: "chevron.down")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .actionSheet(isPresented: $showUnitPicker) {
                    ActionSheet(
                        title: Text("Select Blood Glucose Units"),
                        buttons: [
                            .default(Text("mg/dL")) {
                                onboardingData.units = .mgdL
                                // Adjust values for unit change
                                if onboardingData.units == .mgdL {
                                    onboardingData.targetLow = max(70, onboardingData.targetLow * 18)
                                    onboardingData.targetHigh = max(120, onboardingData.targetHigh * 18)
                                    onboardingData.isf = max(30, onboardingData.isf * 18)
                                }
                            },
                            .default(Text("mmol/L")) {
                                onboardingData.units = .mmolL
                                // Adjust values for unit change
                                if onboardingData.units == .mmolL {
                                    onboardingData.targetLow = max(3.9, onboardingData.targetLow / 18)
                                    onboardingData.targetHigh = max(6.7, onboardingData.targetHigh / 18)
                                    onboardingData.isf = max(1.7, onboardingData.isf / 18)
                                }
                            },
                            .cancel()
                        ]
                    )
                }
            }

            Divider()

            // Target glucose range
            VStack(alignment: .leading, spacing: 12) {
                Text("Target Glucose Range")
                    .font(.headline)

                Text("This range defines your ideal blood glucose values. Trio uses this to calculate insulin doses.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Low target
                VStack(alignment: .leading) {
                    Text("Low Target")
                        .font(.subheadline)

                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(truncating: onboardingData.targetLow as NSNumber) },
                                set: { onboardingData.targetLow = Decimal($0) }
                            ),
                            in: onboardingData.units == .mgdL ? 70 ... 120 : 3.9 ... 6.7,
                            step: onboardingData.units == .mgdL ? 1 : 0.1
                        )
                        .accentColor(.green)

                        Text(
                            "\(numberFormatter.string(from: onboardingData.targetLow as NSNumber) ?? "--") \(onboardingData.units == .mgdL ? "mg/dL" : "mmol/L")"
                        )
                        .frame(width: 80, alignment: .trailing)
                    }
                }
                .padding(.vertical, 4)

                // High target
                VStack(alignment: .leading) {
                    Text("High Target")
                        .font(.subheadline)

                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(truncating: onboardingData.targetHigh as NSNumber) },
                                set: { onboardingData.targetHigh = Decimal($0) }
                            ),
                            in: onboardingData.units == .mgdL ? 
                                Double(truncating: onboardingData.targetLow as NSNumber) + 10 ... 200 : 
                                Double(truncating: onboardingData.targetLow as NSNumber) + 0.6 ... 11.1,
                            step: onboardingData.units == .mgdL ? 1 : 0.1
                        )
                        .accentColor(.green)

                        Text(
                            "\(numberFormatter.string(from: onboardingData.targetHigh as NSNumber) ?? "--") \(onboardingData.units == .mgdL ? "mg/dL" : "mmol/L")"
                        )
                        .frame(width: 80, alignment: .trailing)
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            // Target range visualization
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Target Range")
                    .font(.headline)

                HStack(spacing: 0) {
                    // Below range
                    Rectangle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 50, height: 30)
                        .overlay(
                            Text("Low")
                                .font(.caption)
                                .foregroundColor(.red)
                        )

                    // Target range
                    Rectangle()
                        .fill(Color.green.opacity(0.3))
                        .frame(width: 100, height: 30)
                        .overlay(
                            Text("Target")
                                .font(.caption)
                                .foregroundColor(.green)
                        )

                    // Above range
                    Rectangle()
                        .fill(Color.yellow.opacity(0.3))
                        .frame(width: 50, height: 30)
                        .overlay(
                            Text("High")
                                .font(.caption)
                                .foregroundColor(.orange)
                        )
                }
                .cornerRadius(8)

                // Range values
                HStack(spacing: 0) {
                    Text("\(numberFormatter.string(from: onboardingData.targetLow as NSNumber) ?? "--")")
                        .font(.caption)
                        .frame(width: 50, alignment: .center)

                    Spacer()
                        .frame(width: 100)

                    Text("\(numberFormatter.string(from: onboardingData.targetHigh as NSNumber) ?? "--")")
                        .font(.caption)
                        .frame(width: 50, alignment: .center)
                }

                Text("These values reflect your personal target range and can be adjusted at any time in the Settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding()
    }
}

/// Basal profile step view for setting basal insulin rates.
struct BasalProfileStepView: View {
    @State var onboardingData: OnboardingData
    @State private var showTimeSelector = false
    @State private var selectedBasalIndex: Int?
    @State private var newStartTime: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your basal insulin profile determines how much background insulin you receive throughout the day.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Basal rates list
            VStack(alignment: .leading, spacing: 10) {
                Text("Basal Rates")
                    .font(.headline)

                ForEach(Array(onboardingData.basalRates.enumerated()), id: \.element.id) { index, basalRate in
                    HStack {
                        Text(basalRate.timeFormatted)
                            .frame(width: 80, alignment: .leading)

                        Slider(
                            value: Binding(
                                get: { Double(truncating: onboardingData.basalRates[index].rate as NSNumber) },
                                set: { onboardingData.basalRates[index].rate = Decimal($0) }
                            ),
                            in: 0 ... 5,
                            step: 0.05
                        )
                        .accentColor(.purple)

                        Text("\(String(format: "%.2f", Double(truncating: basalRate.rate as NSNumber))) U/h")
                            .frame(width: 70, alignment: .trailing)

                        // Delete button (not for the first entry at 00:00)
                        if index > 0 {
                            Button(action: {
                                onboardingData.basalRates.remove(at: index)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.05))
                    .cornerRadius(8)
                }
            }

            // Add new basal rate button
            if onboardingData.basalRates.count < 24 {
                Button(action: {
                    showTimeSelector = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Basal Rate")
                    }
                    .foregroundColor(.purple)
                    .padding(.vertical, 8)
                }
            }

            Divider()

            // Basal profile visualization
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Basal Profile")
                    .font(.headline)

                // Simple chart representation
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0 ..< 24) { hour in
                        let rate = basalRateAt(hour: hour)
                        let height = min(120, CGFloat(Double(rate) * 30))

                        VStack {
                            Rectangle()
                                .fill(Color.purple.opacity(0.7))
                                .frame(width: 10, height: height)

                            if hour % 6 == 0 {
                                Text("\(hour):00")
                                    .font(.system(size: 8))
                                    .frame(width: 20)
                                    .rotationEffect(.degrees(-45))
                                    .offset(y: 10)
                            }
                        }
                    }
                }
                .frame(height: 150)
                .padding(.top)

                Text("This chart shows your basal insulin delivery throughout a 24-hour day.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .actionSheet(isPresented: $showTimeSelector) {
            var buttons: [ActionSheet.Button] = []

            // Find available time slots in 1-hour increments
            for hour in 1 ..< 24 {
                let hourInMinutes = hour * 60
                // Check if this hour is already in the profile
                if !onboardingData.basalRates.contains(where: { $0.startTime == hourInMinutes }) {
                    buttons.append(.default(Text("\(String(format: "%02d:00", hour))")) {
                        // Get the current basal rate active at this time
                        let rate = basalRateAt(hour: hour)
                        // Add new basal rate with the same value
                        onboardingData.basalRates.append(
                            OnboardingData.BasalRateEntry(startTime: hourInMinutes, rate: rate)
                        )
                        // Sort basal rates by time
                        onboardingData.basalRates.sort(by: { $0.startTime < $1.startTime })
                    })
                }
            }

            buttons.append(.cancel())

            return ActionSheet(
                title: Text("Select Start Time"),
                message: Text("Choose when this basal rate should start"),
                buttons: buttons
            )
        }
    }

    /// Calculates the basal rate at a specific hour based on the profile.
    private func basalRateAt(hour: Int) -> Decimal {
        let minutes = hour * 60
        // Find the most recent basal rate entry that starts before or at the given hour
        let applicableRate = onboardingData.basalRates
            .filter { $0.startTime <= minutes }
            .sorted(by: { $0.startTime > $1.startTime })
            .first

        return applicableRate?.rate ?? Decimal(1.0)
    }
}

/// Carb ratio step view for setting insulin-to-carb ratio.
struct CarbRatioStepView: View {
    @State var onboardingData: OnboardingData

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your carb ratio tells how many grams of carbohydrates one unit of insulin will cover.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Text("Carb Ratio")
                    .font(.headline)

                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(truncating: onboardingData.carbRatio as NSNumber) },
                            set: { onboardingData.carbRatio = Decimal($0) }
                        ),
                        in: 2 ... 30,
                        step: 0.5
                    )
                    .accentColor(.orange)

                    // Display the current value
                    Text("\(formatter.string(from: onboardingData.carbRatio as NSNumber) ?? "--") g/U")
                        .frame(width: 80, alignment: .trailing)
                }

                // Example calculation
                VStack(alignment: .leading, spacing: 8) {
                    Text("Example Calculation")
                        .font(.headline)
                        .padding(.top)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("For 45g of carbs, you would need:")
                            .font(.subheadline)

                        let insulinNeeded = 45 / Double(truncating: onboardingData.carbRatio as NSNumber)
                        Text(
                            "45g ÷ \(formatter.string(from: onboardingData.carbRatio as NSNumber) ?? "--") = \(String(format: "%.1f", insulinNeeded)) units of insulin"
                        )
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.orange)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding(.vertical, 4)

                    // Information about the carb ratio
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What This Means")
                            .font(.headline)
                            .padding(.top, 8)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("• A ratio of 10 g/U means 1 unit of insulin covers 10g of carbs")
                            Text("• A lower number means you need more insulin for the same amount of carbs")
                            Text("• A higher number means you need less insulin for the same amount of carbs")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }

            // Visualization of carb ratio
            VStack(alignment: .leading, spacing: 8) {
                Text("Visual Reference")
                    .font(.headline)
                    .padding(.top)

                HStack(spacing: 20) {
                    VStack {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text("\(formatter.string(from: onboardingData.carbRatio as NSNumber) ?? "--")g")
                            .font(.headline)
                        Text("Carbs")
                            .font(.caption)
                    }

                    Text("=")
                        .font(.title)

                    VStack {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                        Text("1U")
                            .font(.headline)
                        Text("Insulin")
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding()
    }
}

/// Insulin sensitivity step view for setting insulin sensitivity factor.
struct InsulinSensitivityStepView: View {
    @State var onboardingData: OnboardingData

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = onboardingData.units == .mmolL ? 1 : 0
        return formatter
    }

    private var ispRange: ClosedRange<Double> {
        if onboardingData.units == .mgdL {
            return 10 ... 100
        } else {
            return 0.5 ... 5.5
        }
    }

    private var ispStep: Double {
        onboardingData.units == .mgdL ? 1 : 0.1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your insulin sensitivity factor (ISF) indicates how much one unit of insulin will lower your blood glucose.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Text("Insulin Sensitivity Factor")
                    .font(.headline)

                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(truncating: onboardingData.isf as NSNumber) },
                            set: { onboardingData.isf = Decimal($0) }
                        ),
                        in: ispRange,
                        step: ispStep
                    )
                    .accentColor(.red)

                    // Display the current value
                    Text(
                        "\(numberFormatter.string(from: onboardingData.isf as NSNumber) ?? "--") \(onboardingData.units == .mgdL ? "mg/dL" : "mmol/L")"
                    )
                    .frame(width: 80, alignment: .trailing)
                }

                // Example calculation
                VStack(alignment: .leading, spacing: 8) {
                    Text("Example Calculation")
                        .font(.headline)
                        .padding(.top)

                    VStack(alignment: .leading, spacing: 4) {
                        // Current glucose is 40 mg/dL or 2.2 mmol/L above target
                        let aboveTarget = onboardingData.units == .mgdL ? 40.0 : 2.2
                        let insulinNeeded = aboveTarget / Double(truncating: onboardingData.isf as NSNumber)

                        Text(
                            "If you are \(numberFormatter.string(from: NSNumber(value: aboveTarget)) ?? "--") \(onboardingData.units == .mgdL ? "mg/dL" : "mmol/L") above target:"
                        )
                        .font(.subheadline)

                        Text(
                            "\(numberFormatter.string(from: NSNumber(value: aboveTarget)) ?? "--") ÷ \(numberFormatter.string(from: onboardingData.isf as NSNumber) ?? "--") = \(String(format: "%.1f", insulinNeeded)) units of insulin"
                        )
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.red)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding(.vertical, 4)

                    // Information about ISF
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What This Means")
                            .font(.headline)
                            .padding(.top, 8)

                        VStack(alignment: .leading, spacing: 4) {
                            if onboardingData.units == .mgdL {
                                Text("• An ISF of 50 mg/dL means 1 unit of insulin lowers your BG by 50 mg/dL")
                                Text("• A lower number means you're more sensitive to insulin")
                                Text("• A higher number means you're less sensitive to insulin")
                            } else {
                                Text("• An ISF of 2.8 mmol/L means 1 unit of insulin lowers your BG by 2.8 mmol/L")
                                Text("• A lower number means you're more sensitive to insulin")
                                Text("• A higher number means you're less sensitive to insulin")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }

            // Visualization of ISF
            VStack(alignment: .leading, spacing: 8) {
                Text("Visual Reference")
                    .font(.headline)
                    .padding(.top)

                HStack(spacing: 20) {
                    VStack {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                        Text("1U")
                            .font(.headline)
                        Text("Insulin")
                            .font(.caption)
                    }

                    Text("⟹")
                        .font(.title)

                    VStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.red)
                        Text("\(numberFormatter.string(from: onboardingData.isf as NSNumber) ?? "--")")
                            .font(.headline)
                        Text(onboardingData.units == .mgdL ? "mg/dL" : "mmol/L")
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding()
    }
}

/// Completed step view shown at the end of onboarding.
struct CompletedStepView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
                .padding()

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(
                "You've successfully completed the initial setup of Trio. Your settings have been saved and you're ready to start using the app."
            )
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                SettingItemView(icon: "target", title: "Glucose Target", description: "Your target range is set")
                SettingItemView(
                    icon: "chart.xyaxis.line",
                    title: "Basal Profile",
                    description: "Your basal profile is configured"
                )
                SettingItemView(icon: "fork.knife", title: "Carb Ratio", description: "Your carb ratio is defined")
                SettingItemView(icon: "drop.fill", title: "Insulin Sensitivity", description: "Your ISF is established")
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)

            Text("Remember, you can adjust these settings at any time in the app settings if needed.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

/// A reusable view for displaying setting items in the completed step.
struct SettingItemView: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.green)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark")
                .foregroundColor(.green)
        }
        .padding(.vertical, 8)
    }
}
