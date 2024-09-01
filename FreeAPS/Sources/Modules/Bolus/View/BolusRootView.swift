import Charts
import CoreData
import LoopKitUI
import SwiftUI
import Swinject

extension Bolus {
    struct RootView: BaseView {
        enum FocusedField {
            case carbs
            case fat
            case protein
            case bolus
        }

        @FocusState private var focusedField: FocusedField?

        let resolver: Resolver

        @StateObject var state = StateModel()

        @State private var showPresetSheet = false
        @State private var autofocus: Bool = true
        @State private var calculatorDetent = PresentationDetent.medium
        @State private var pushed: Bool = false
        @State private var debounce: DispatchWorkItem?

        private enum Config {
            static let dividerHeight: CGFloat = 2
            static let spacing: CGFloat = 3
        }

        @Environment(\.colorScheme) var colorScheme

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var mealFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        private var gluoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
            } else { formatter.maximumFractionDigits = 0 }
            return formatter
        }

        private var fractionDigits: Int {
            if state.units == .mmolL {
                return 1
            } else { return 0 }
        }

        private var color: LinearGradient {
            colorScheme == .dark ? LinearGradient(
                gradient: Gradient(colors: [
                    Color.bgDarkBlue,
                    Color.bgDarkerDarkBlue
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
                :
                LinearGradient(
                    gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
        }

        /// Handles macro input (carb, fat, protein) in a debounced fashion.
        func handleDebouncedInput() {
            debounce?.cancel()
            debounce = DispatchWorkItem { [self] in
                state.insulinCalculated = state.calculateInsulin()
                Task {
                    await state.updateForecasts()
                }
            }
            if let debounce = debounce {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: debounce)
            }
        }

        @ViewBuilder private func proteinAndFat() -> some View {
            HStack {
                Text("Fat").foregroundColor(.orange)
                Spacer()
                TextFieldWithToolBar(
                    text: $state.fat,
                    placeholder: "0",
                    keyboardType: .numberPad,
                    numberFormatter: mealFormatter,
                    previousTextField: { focusOnPreviousTextField(index: 2) },
                    nextTextField: { focusOnNextTextField(index: 2) }
                ).focused($focusedField, equals: .fat)
                Text("g").foregroundColor(.secondary)
            }
            HStack {
                Text("Protein").foregroundColor(.red)
                Spacer()
                TextFieldWithToolBar(
                    text: $state.protein,
                    placeholder: "0",
                    keyboardType: .numberPad,
                    numberFormatter: mealFormatter,
                    previousTextField: { focusOnPreviousTextField(index: 3) },
                    nextTextField: { focusOnNextTextField(index: 3) }
                ).focused($focusedField, equals: .protein)
                Text("g").foregroundColor(.secondary)
            }
        }

        @ViewBuilder private func carbsTextField() -> some View {
            HStack {
                Text("Carbs").fontWeight(.semibold)
                Spacer()
                TextFieldWithToolBar(
                    text: $state.carbs,
                    placeholder: "0",
                    keyboardType: .numberPad,
                    numberFormatter: mealFormatter,
                    previousTextField: { focusOnPreviousTextField(index: 1) },
                    nextTextField: { focusOnNextTextField(index: 1) }
                ).focused($focusedField, equals: .carbs)
                    .onChange(of: state.carbs) { _ in
                        handleDebouncedInput()
                    }
                Text("g").foregroundColor(.secondary)
            }
        }

        func focusOnPreviousTextField(index: Int) {
            switch index {
            case 2:
                focusedField = .carbs
            case 3:
                focusedField = .fat
            case 4:
                focusedField = .protein
            default:
                break
            }
        }

        func focusOnNextTextField(index: Int) {
            switch index {
            case 1:
                focusedField = .fat
            case 2:
                focusedField = .protein
            case 3:
                focusedField = .bolus
            default:
                break
            }
        }

        var body: some View {
            ZStack(alignment: .center) {
                VStack {
                    Form {
                        Section {
                            ForeCastChart(state: state, units: $state.units, stops: state.stops)
                                .padding(.vertical)
                        }.listRowBackground(Color.chart)

                        Section {
                            carbsTextField()

                            DisclosureGroup("Extras") {
                                if state.useFPUconversion {
                                    proteinAndFat()
                                }

                                // Time
                                HStack {
                                    Text("Time").foregroundStyle(Color.secondary)
                                    Spacer()
                                    if !pushed {
                                        Button {
                                            pushed = true
                                        } label: { Text("Now") }.buttonStyle(.borderless).foregroundColor(.secondary)
                                            .padding(.trailing, 5)
                                    } else {
                                        Button { state.date = state.date.addingTimeInterval(-15.minutes.timeInterval) }
                                        label: { Image(systemName: "minus.circle") }.tint(.blue).buttonStyle(.borderless)
                                        DatePicker(
                                            "Time",
                                            selection: $state.date,
                                            displayedComponents: [.hourAndMinute]
                                        ).controlSize(.mini)
                                            .labelsHidden()
                                        Button {
                                            state.date = state.date.addingTimeInterval(15.minutes.timeInterval)
                                        }
                                        label: { Image(systemName: "plus.circle") }.tint(.blue).buttonStyle(.borderless)
                                    }
                                }

                                // Notes
                                HStack {
                                    Image(systemName: "square.and.pencil").foregroundColor(.secondary)
                                    TextFieldWithToolBarString(text: $state.note, placeholder: "", maxLength: 25)
                                }
                            }
                        }.listRowBackground(Color.chart)

                        Section {
                            HStack {
                                Button(action: {
                                    state.showInfo.toggle()
                                }, label: {
                                    Image(systemName: "info.circle")
                                    Text("Calculations")
                                })
                                    .foregroundStyle(.blue)
                                    .font(.footnote)
                                    .buttonStyle(PlainButtonStyle())
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if state.fattyMeals {
                                    Spacer()
                                    Toggle(isOn: $state.useFattyMealCorrectionFactor) {
                                        Text("Fatty Meal")
                                    }
                                    .toggleStyle(CheckboxToggleStyle())
                                    .font(.footnote)
                                    .onChange(of: state.useFattyMealCorrectionFactor) { _ in
                                        state.insulinCalculated = state.calculateInsulin()
                                        if state.useFattyMealCorrectionFactor {
                                            state.useSuperBolus = false
                                        }
                                    }
                                }
                                if state.sweetMeals {
                                    Spacer()
                                    Toggle(isOn: $state.useSuperBolus) {
                                        Text("Super Bolus")
                                    }
                                    .toggleStyle(CheckboxToggleStyle())
                                    .font(.footnote)
                                    .onChange(of: state.useSuperBolus) { _ in
                                        state.insulinCalculated = state.calculateInsulin()
                                        if state.useSuperBolus {
                                            state.useFattyMealCorrectionFactor = false
                                        }
                                    }
                                }
                            }

                            HStack {
                                Text("Recommended Bolus")
                                Spacer()
                                Text(
                                    formatter
                                        .string(from: Double(state.insulinCalculated) as NSNumber) ?? ""
                                )
                                Text(
                                    NSLocalizedString(
                                        " U",
                                        comment: "Unit in number of units delivered (keep the space character!)"
                                    )
                                ).foregroundColor(.secondary)
                            }.contentShape(Rectangle())
                                .onTapGesture { state.amount = state.insulinCalculated }

                            HStack {
                                Text("Bolus")
                                Spacer()
                                TextFieldWithToolBar(
                                    text: $state.amount,
                                    placeholder: "0",
                                    textColor: colorScheme == .dark ? .white : .blue,
                                    maxLength: 5,
                                    numberFormatter: formatter,
                                    previousTextField: { focusOnPreviousTextField(index: 4) },
                                    nextTextField: { focusOnNextTextField(index: 4) }
                                ).focused($focusedField, equals: .bolus)
                                    .onChange(of: state.amount) { _ in
                                        Task {
                                            await state.updateForecasts()
                                        }
                                    }
                                Text(" U").foregroundColor(.secondary)
                            }

                            HStack {
                                Text("External insulin")
                                Spacer()
                                Toggle("", isOn: $state.externalInsulin).toggleStyle(Checkbox())
                            }
                        }.listRowBackground(Color.chart)
                    }
                }
                .safeAreaInset(edge: .bottom, content: {
                    stickyButton
                })
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .blur(radius: state.waitForSuggestion ? 5 : 0)

                if state.waitForSuggestion {
                    CustomProgressView(text: progressText.rawValue)
                }
            }
            .scrollContentBackground(.hidden).background(color)
            .blur(radius: state.showInfo ? 3 : 0)
            .navigationTitle("Treatments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        state.hideModal()
                    } label: {
                        Text("Close")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        showPresetSheet = true
                    }, label: {
                        HStack {
                            Text("Presets")
                            Image(systemName: "plus")
                        }
                    })
                }
            })
            .onAppear {
                configureView {
                    state.insulinCalculated = state.calculateInsulin()
                }
            }
            .onDisappear {
                state.addButtonPressed = false
            }
            .sheet(isPresented: $state.showInfo) {
                PopupView(state: state)
                    .presentationDetents(
                        [.fraction(0.9), .large],
                        selection: $calculatorDetent
                    )
            }
            .sheet(isPresented: $showPresetSheet, onDismiss: {
                showPresetSheet = false
            }) {
                MealPresetView(state: state)
            }
        }

        var progressText: ProgressText {
            switch (state.amount > 0, state.carbs > 0) {
            case (true, true):
                return .updatingIOBandCOB
            case (false, true):
                return .updatingCOB
            case (true, false):
                return .updatingIOB
            default:
                return .updatingTreatments
            }
        }

        var stickyButton: some View {
            ZStack {
                Rectangle()
                    .frame(width: UIScreen.main.bounds.width, height: 120).offset(y: 40)
                    .shadow(
                        color: colorScheme == .dark ? Color(red: 0.02745098039, green: 0.1098039216, blue: 0.1411764706) :
                            Color.black.opacity(0.33),
                        radius: 3
                    )
                    .foregroundStyle(Color.chart)

                Button {
                    state.invokeTreatmentsTask()
                } label: {
                    taskButtonLabel
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(minHeight: 50)
                }
                .disabled(disableTaskButton)
                .background(limitExceeded ? Color(.systemRed) : Color(.systemBlue))
                .shadow(radius: 3)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()
                .offset(y: 20)
            }
        }

        private var taskButtonLabel: some View {
            if pumpBolusLimitExceeded {
                return Text("Max Bolus of \(state.maxBolus.description) U Exceeded")
            } else if externalBolusLimitExceeded {
                return Text("Max External Bolus of \(state.maxExternal.description) U Exceeded")
            } else if carbLimitExceeded {
                return Text("Max Carbs of \(state.maxCarbs.description) g Exceeded")
            } else if fatLimitExceeded {
                return Text("Max Fat of \(state.maxFat.description) g Exceeded")
            } else if proteinLimitExceeded {
                return Text("Max Protein of \(state.maxProtein.description) g Exceeded")
            }

            let hasInsulin = state.amount > 0
            let hasCarbs = state.carbs > 0
            let hasFatOrProtein = state.fat > 0 || state.protein > 0
            let bolusString = state.externalInsulin ? "External Insulin" : "Enact Bolus"

            switch (hasInsulin, hasCarbs, hasFatOrProtein) {
            case (true, true, true):
                return Text("Log Meal and \(bolusString)")
            case (true, true, false):
                return Text("Log Carbs and \(bolusString)")
            case (true, false, true):
                return Text("Log FPU and \(bolusString)")
            case (true, false, false):
                return Text(state.externalInsulin ? "Log External Insulin" : "Enact Bolus")
            case (false, true, true):
                return Text("Log Meal")
            case (false, true, false):
                return Text("Log Carbs")
            case (false, false, true):
                return Text("Log FPU")
            default:
                return Text("Continue Without Treatment")
            }
        }

        private var pumpBolusLimitExceeded: Bool {
            !state.externalInsulin && state.amount > state.maxBolus
        }

        private var externalBolusLimitExceeded: Bool {
            state.externalInsulin && state.amount > state.maxExternal
        }

        private var carbLimitExceeded: Bool {
            state.carbs > state.maxCarbs
        }

        private var fatLimitExceeded: Bool {
            state.fat > state.maxFat
        }

        private var proteinLimitExceeded: Bool {
            state.protein > state.maxProtein
        }

        private var limitExceeded: Bool {
            pumpBolusLimitExceeded || externalBolusLimitExceeded || carbLimitExceeded || fatLimitExceeded || proteinLimitExceeded
        }

        private var disableTaskButton: Bool {
            state.addButtonPressed || limitExceeded
        }
    }

    struct DividerDouble: View {
        var body: some View {
            VStack(spacing: 2) {
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.gray.opacity(0.65))
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.gray.opacity(0.65))
            }
            .frame(height: 4)
            .padding(.vertical)
        }
    }

    struct DividerCustom: View {
        var body: some View {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.gray.opacity(0.65))
                .padding(.vertical)
        }
    }
}

// fix iOS 15 bug
struct ActivityIndicator: UIViewRepresentable {
    @Binding var isAnimating: Bool
    let style: UIActivityIndicatorView.Style

    func makeUIView(context _: UIViewRepresentableContext<ActivityIndicator>) -> UIActivityIndicatorView {
        UIActivityIndicatorView(style: style)
    }

    func updateUIView(_ uiView: UIActivityIndicatorView, context _: UIViewRepresentableContext<ActivityIndicator>) {
        isAnimating ? uiView.startAnimating() : uiView.stopAnimating()
    }
}
