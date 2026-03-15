import SwiftUI

struct CarbsView: View {
    @EnvironmentObject var state: WatchStateModel

    // Selected nutrient
    enum Selection: String {
        case carbs
        case protein
        case fat
    }

    @State var selection: Selection = .carbs
    @State var carbAmount = 0.0
    @State var fatAmount = 0.0
    @State var proteinAmount = 0.0
    @State var colorOfselection: Color = .darkGray
    // @State var displayPresets: Bool = false

    var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 0
        formatter.maximum = (state.maxCOB ?? 120) as NSNumber
        formatter.maximumFractionDigits = 0
        formatter.allowsFloats = false
        return formatter
    }

    var body: some View {
        VStack {
            // nutrient
            carbs
            if state.displayFatAndProteinOnWatch {
                Spacer()
                fat
                Spacer()
                protein
            }
            buttonStack
        }
        .onAppear { carbAmount = Double(state.carbsRequired ?? 0) }
    }

    var nutrient: some View {
        HStack {
            switch selection {
            case .protein:
                Text("Protein")
            case .fat:
                Text("Fat")
            default:
                Text("Carbs")
            }
        }.font(.footnote).frame(maxWidth: .infinity, alignment: .center)
    }

    var carbs: some View {
        HStack {
            if selection == .carbs {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    let newValue = carbAmount - 5
                    carbAmount = max(newValue, 0)
                }
                label: {
                    HStack {
                        Image(systemName: "minus")
                        Text("") // Ugly fix to increase active tapping (button) area.
                    }
                }
                .buttonStyle(.borderless).padding(.leading, 5)
                .tint(selection == .carbs ? .blue : .none)
            }
            Spacer()
            Text("🥨")
            Spacer()
            Text(numberFormatter.string(from: carbAmount as NSNumber)! + " g")
                .font(selection == .carbs ? .title : .title3)
                .focusable(selection == .carbs)
                .digitalCrownRotation(
                    $carbAmount,
                    from: 0,
                    through: Double(state.maxCOB ?? 120),
                    by: 1,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
            Spacer()
            if selection == .carbs {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    let newValue = carbAmount + 5
                    carbAmount = min(newValue, Double(state.maxCOB ?? 120))
                } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).padding(.trailing, 5)
                    .tint(selection == .carbs ? .blue : .none)
            }
        }
        .minimumScaleFactor(0.7)
        .onTapGesture {
            select(entry: .carbs)
        }
        .background(selection == .carbs && state.displayFatAndProteinOnWatch ? colorOfselection : .black)
        .padding(.top)
    }

    var protein: some View {
        HStack {
            if selection == .protein {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    let newValue = proteinAmount - 5
                    proteinAmount = max(newValue, 0)
                } label: {
                    HStack {
                        Image(systemName: "minus")
                        Text("") // Ugly fix to increase active tapping (button) area.
                    }
                }
                .buttonStyle(.borderless).padding(.leading, 5)
                .tint(selection == .protein ? .blue : .none)
            }
            Spacer()
            Text("🍗")
            Spacer()
            Text(numberFormatter.string(from: proteinAmount as NSNumber)! + " g")
                .font(selection == .protein ? .title : .title3)
                .foregroundStyle(.red)
                .focusable(selection == .protein)
                .digitalCrownRotation(
                    $proteinAmount,
                    from: 0,
                    through: Double(240),
                    by: 1,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
            Spacer()
            if selection == .protein {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    let newValue = proteinAmount + 5
                    proteinAmount = min(newValue, Double(240))
                } label: { Image(systemName: "plus") }.buttonStyle(.borderless).padding(.trailing, 5)
                    .tint(selection == .protein ? .blue : .none)
            }
        }
        .minimumScaleFactor(0.7)
        .onTapGesture {
            select(entry: .protein)
        }
        .background(selection == .protein ? colorOfselection : .black)
    }

    var fat: some View {
        HStack {
            if selection == .fat {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    let newValue = fatAmount - 5
                    fatAmount = max(newValue, 0)
                } label: {
                    HStack {
                        Image(systemName: "minus")
                        Text("") // Ugly fix to increase active tapping (button) area.
                    }
                }
                .buttonStyle(.borderless).padding(.leading, 5)
                .tint(selection == .fat ? .blue : .none)
            }
            Spacer()
            Text("🧀")
            Spacer()
            Text(numberFormatter.string(from: fatAmount as NSNumber)! + " g")
                .font(selection == .fat ? .title : .title3)
                .foregroundColor(.loopYellow)
                .focusable(selection == .fat)
                .digitalCrownRotation(
                    $fatAmount,
                    from: 0,
                    through: Double(240),
                    by: 1,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
            Spacer()
            if selection == .fat {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    let newValue = fatAmount + 5
                    fatAmount = min(newValue, Double(240))
                } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).padding(.trailing, 5)
                    .tint(selection == .fat ? .blue : .none)
            }
        }
        .minimumScaleFactor(0.7)
        .onTapGesture {
            select(entry: .fat)
        }
        .background(selection == .fat ? colorOfselection : .black)
    }

    var buttonStack: some View {
        HStack(spacing: 25) {
            /* To do: display the actual meal presets
             Button {
                 displayPresets.toggle()
             }
             label: { Image(systemName: "menucard.fill") }
                 .buttonStyle(.borderless)
             */
            Button {
                WKInterfaceDevice.current().play(.click)
                // Get amount from displayed string
                let amountCarbs = Int(numberFormatter.string(from: carbAmount as NSNumber)!) ?? Int(carbAmount.rounded())
                let amountFat = Int(numberFormatter.string(from: fatAmount as NSNumber)!) ?? Int(fatAmount.rounded())
                let amountProtein = Int(numberFormatter.string(from: proteinAmount as NSNumber)!) ??
                    Int(proteinAmount.rounded())
                state.addMeal(amountCarbs, fat: amountFat, protein: amountProtein)
            }
            label: { Text("Save") }
                .buttonStyle(.borderless)
                .font(.callout)
                .foregroundColor(carbAmount > 0 || fatAmount > 0 || proteinAmount > 0 ? .blue : .secondary)
                .disabled(carbAmount <= 0 && fatAmount <= 0 && proteinAmount <= 0)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.top)
    }

    private func select(entry: Selection) {
        selection = entry
    }
}

struct CarbsView_Previews: PreviewProvider {
    static var previews: some View {
        let state = WatchStateModel()
        state.carbsRequired = 120
        return Group {
            CarbsView()
            CarbsView().previewDevice("Apple Watch Series 5 - 40mm")
            CarbsView().previewDevice("Apple Watch Series 3 - 38mm")
        }
        .environmentObject(state)
    }
}
