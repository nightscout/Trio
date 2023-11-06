import SwiftUI
import Swinject

extension Bolus {
    struct DefaultBolusCalcRootView: BaseView {
        let resolver: Resolver
        let waitForSuggestion: Bool
        let fetch: Bool
        @StateObject var state = StateModel()

        @State private var isAddInsulinAlertPresented = false
        @State private var presentInfo = false
        @State private var displayError = false
        @State private var keepForNextWiew: Bool = false

        @Environment(\.colorScheme) var colorScheme

        @FetchRequest(
            entity: Meals.entity(),
            sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)]
        ) var meal: FetchedResults<Meals>

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var fractionDigits: Int {
            if state.units == .mmolL {
                return 1
            } else { return 0 }
        }

        var body: some View {
            Form {
                if fetch {
                    Section {
                        mealEntries
                    } header: { Text("Meal Summary") }
                }

                Section {
                    if state.waitForSuggestion {
                        HStack {
                            Text("Wait please").foregroundColor(.secondary)
                            Spacer()
                            ActivityIndicator(isAnimating: .constant(true), style: .medium) // fix iOS 15 bug
                        }
                    } else {
                        HStack {
                            Text("Insulin recommended")
                            Image(systemName: "info.bubble")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.primary, .blue)
                                .onTapGesture {
                                    presentInfo.toggle()
                                }

                            Spacer()

                            Text(
                                formatter
                                    .string(from: state.insulinRecommended as NSNumber)! +
                                    NSLocalizedString(" U", comment: "Insulin unit")
                            ).foregroundColor((state.error && state.insulinRecommended > 0) ? .red : .secondary)
                                .onTapGesture {
                                    if state.error, state.insulinRecommended > 0 { displayError = true }
                                    else { state.amount = state.insulinRecommended }
                                }
                        }.contentShape(Rectangle())

                        HStack {
                            Text("Amount")
                            Spacer()
                            DecimalTextField(
                                "0",
                                value: $state.amount,
                                formatter: formatter,
                                autofocus: true,
                                cleanInput: true
                            )
                            Text(!(state.amount > state.maxBolus) ? "U" : "😵").foregroundColor(.secondary)
                        }
                    }
                } header: { Text("Bolus") }

                if !state.waitForSuggestion {
                    if state.amount > 0 {
                        Section {
                            Button {
                                keepForNextWiew = true
                                state.add()
                            }
                            label: { Text(!(state.amount > state.maxBolus) ? "Enact bolus" : "Max Bolus exceeded!") }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .disabled(
                                    state.amount <= 0 || state.amount > state.maxBolus
                                )
                        }
                    }
                }
                if state.amount <= 0 {
                    Section {
                        Button {
                            keepForNextWiew = true
                            state.showModal(for: nil)
                        }
                        label: { Text("Continue without bolus") }.frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .alert(isPresented: $displayError) {
                Alert(
                    title: Text("Warning!"),
                    message: Text("\n" + alertString() + "\n"),
                    primaryButton: .destructive(
                        Text("Add"),
                        action: {
                            state.amount = state.insulinRecommended
                            displayError = false
                        }
                    ),
                    secondaryButton: .cancel()
                )
            }.onAppear {
                configureView {
                    state.waitForSuggestionInitial = waitForSuggestion
                    state.waitForSuggestion = waitForSuggestion
                }
            }

            .onDisappear {
                if fetch, hasFatOrProtein, !keepForNextWiew, !state.useCalc {
                    state.delete(deleteTwice: true, id: meal.first?.id ?? "")
                } else if fetch, !keepForNextWiew, !state.useCalc {
                    state.delete(deleteTwice: false, id: meal.first?.id ?? "")
                }
            }

            .navigationTitle("Enact Bolus")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button {
                    carbssView()
                }
                label: { Text(fetch ? "Back" : "Meal") },

                trailing: Button { state.hideModal() }
                label: { Text("Close") }
            )
            .popup(isPresented: presentInfo, alignment: .center, direction: .bottom) {
                bolusInfo
            }
        }

        var changed: Bool {
            ((meal.first?.carbs ?? 0) > 0) || ((meal.first?.fat ?? 0) > 0) || ((meal.first?.protein ?? 0) > 0)
        }

        var hasFatOrProtein: Bool {
            ((meal.first?.fat ?? 0) > 0) || ((meal.first?.protein ?? 0) > 0)
        }

        func carbssView() {
            let id_ = meal.first?.id ?? ""
            if fetch {
                keepForNextWiew = true
                state.backToCarbsView(complexEntry: fetch, id_)
            } else {
                state.showModal(for: .addCarbs(editMode: false))
            }
        }

        var mealEntries: some View {
            VStack {
                if let carbs = meal.first?.carbs, carbs > 0 {
                    HStack {
                        Text("Carbs")
                        Spacer()
                        Text(carbs.formatted())
                        Text("g")
                    }.foregroundColor(.secondary)
                }
                if let fat = meal.first?.fat, fat > 0 {
                    HStack {
                        Text("Fat")
                        Spacer()
                        Text(fat.formatted())
                        Text("g")
                    }.foregroundColor(.secondary)
                }
                if let protein = meal.first?.protein, protein > 0 {
                    HStack {
                        Text("Protein")
                        Spacer()
                        Text(protein.formatted())
                        Text("g")
                    }.foregroundColor(.secondary)
                }
                if let note = meal.first?.note, note != "" {
                    HStack {
                        Text("Note")
                        Spacer()
                        Text(note)
                    }.foregroundColor(.secondary)
                }
            }
        }

        var bolusInfo: some View {
            VStack {
                // Variables
                VStack(spacing: 3) {
                    HStack {
                        Text("Eventual Glucose").foregroundColor(.secondary)
                        let evg = state.units == .mmolL ? Decimal(state.evBG).asMmolL : Decimal(state.evBG)
                        Text(evg.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))))
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Target Glucose").foregroundColor(.secondary)
                        let target = state.units == .mmolL ? state.target.asMmolL : state.target
                        Text(target.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))))
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("ISF").foregroundColor(.secondary)
                        let isf = state.isf
                        Text(isf.formatted())
                        Text(state.units.rawValue + NSLocalizedString("/U", comment: "/Insulin unit"))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("ISF:")
                        Text("Insulin Sensitivity")
                    }.foregroundColor(.secondary).italic()
                    if state.percentage != 100 {
                        HStack {
                            Text("Percentage setting").foregroundColor(.secondary)
                            let percentage = state.percentage
                            Text(percentage.formatted())
                            Text("%").foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Text("Formula:")
                        Text("(Eventual Glucose - Target) / ISF")
                    }.foregroundColor(.secondary).italic().padding(.top, 5)
                }
                .font(.footnote)
                .padding(.top, 10)
                Divider()
                // Formula
                VStack(spacing: 5) {
                    let unit = NSLocalizedString(
                        " U",
                        comment: "Unit in number of units delivered (keep the space character!)"
                    )
                    let color: Color = (state.percentage != 100 && state.insulin > 0) ? .secondary : .blue
                    let fontWeight: Font.Weight = (state.percentage != 100 && state.insulin > 0) ? .regular : .bold
                    HStack {
                        Text(NSLocalizedString("Insulin recommended", comment: "") + ":").font(.callout)
                        Text(state.insulin.formatted() + unit).font(.callout).foregroundColor(color).fontWeight(fontWeight)
                    }
                    if state.percentage != 100, state.insulin > 0 {
                        Divider()
                        HStack { Text(state.percentage.formatted() + " % ->").font(.callout).foregroundColor(.secondary)
                            Text(
                                state.insulinRecommended.formatted() + unit
                            ).font(.callout).foregroundColor(.blue).bold()
                        }
                    }
                }
                // Warning
                if state.error, state.insulinRecommended > 0 {
                    VStack(spacing: 5) {
                        Divider()
                        Text("Warning!").font(.callout).bold().foregroundColor(.orange)
                        Text(alertString()).font(.footnote)
                        Divider()
                    }.padding(.horizontal, 10)
                }
                // Footer
                if !(state.error && state.insulinRecommended > 0) {
                    VStack {
                        Text(
                            "Carbs and previous insulin are included in the glucose prediction, but if the Eventual Glucose is lower than the Target Glucose, a bolus will not be recommended."
                        ).font(.caption2).foregroundColor(.secondary)
                    }.padding(20)
                }
                // Hide button
                VStack {
                    Button { presentInfo = false }
                    label: { Text("Hide") }.frame(maxWidth: .infinity, alignment: .center).font(.callout)
                        .foregroundColor(.blue)
                }.padding(.bottom, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(colorScheme == .dark ? UIColor.systemGray4 : UIColor.systemGray4))
            )
        }

        // Localize the Oref0 error/warning strings. The default should never be returned
        private func alertString() -> String {
            switch state.errorString {
            case 1,
                 2:
                return NSLocalizedString(
                    "Eventual Glucose > Target Glucose, but glucose is predicted to first drop down to ",
                    comment: "Bolus pop-up / Alert string. Make translations concise!"
                ) + state.minGuardBG
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))) + " " + state.units
                    .rawValue + ", " +
                    NSLocalizedString(
                        "which is below your Threshold (",
                        comment: "Bolus pop-up / Alert string. Make translations concise!"
                    ) + state
                    .threshold.formatted() + " " + state.units.rawValue + ")"
            case 3:
                return NSLocalizedString(
                    "Eventual Glucose > Target Glucose, but glucose is climbing slower than expected. Expected: ",
                    comment: "Bolus pop-up / Alert string. Make translations concise!"
                ) +
                    state.expectedDelta
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))) +
                    NSLocalizedString(". Climbing: ", comment: "Bolus pop-up / Alert string. Make translatons concise!") + state
                    .minDelta.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
            case 4:
                return NSLocalizedString(
                    "Eventual Glucose > Target Glucose, but glucose is falling faster than expected. Expected: ",
                    comment: "Bolus pop-up / Alert string. Make translations concise!"
                ) +
                    state.expectedDelta
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))) +
                    NSLocalizedString(". Falling: ", comment: "Bolus pop-up / Alert string. Make translations concise!") + state
                    .minDelta.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
            case 5:
                return NSLocalizedString(
                    "Eventual Glucose > Target Glucose, but glucose is changing faster than expected. Expected: ",
                    comment: "Bolus pop-up / Alert string. Make translations concise!"
                ) +
                    state.expectedDelta
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))) +
                    NSLocalizedString(". Changing: ", comment: "Bolus pop-up / Alert string. Make translations concise!") + state
                    .minDelta.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
            case 6:
                return NSLocalizedString(
                    "Eventual Glucose > Target Glucose, but glucose is predicted to first drop down to ",
                    comment: "Bolus pop-up / Alert string. Make translations concise!"
                ) + state
                    .minPredBG
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))) + " " + state
                    .units
                    .rawValue
            default:
                return "Ignore Warning..."
            }
        }
    }
}
