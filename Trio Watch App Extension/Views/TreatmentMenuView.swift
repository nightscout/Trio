import SwiftUI

struct TreatmentMenuView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var selectedTreatment: TreatmentOption?

    let treatments = TreatmentOption.allCases

    var body: some View {
        NavigationView {
            List {
                ForEach(treatments) { treatment in
                    Button(action: {
                        selectedTreatment = treatment
                        presentationMode.wrappedValue.dismiss() // Close after selecting
                    }) {
                        HStack(alignment: .center) {
                            switch treatment {
                            case .mealBolusCombo:
                                mealIcon

                                // Plus Icon
                                Image(systemName: "plus")
                                    .font(.caption)
                                    .bold()
                                    .frame(width: 24, height: 24)

                                bolusIcon
                            case .meal:
                                mealIcon

                            case .bolus:
                                bolusIcon
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PressableIconButtonStyle())
                }.listRowBackground(Color.clear)
            }.navigationTitle("Pick Treatment")
        }
    }

    var mealIcon: some View {
        Image(systemName: "fork.knife")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 22, height: 22) // Icon size
            .padding(10)
            .background(Color.orange)
            .clipShape(Circle())
    }

    var bolusIcon: some View {
        Image(systemName: "syringe.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 22, height: 22) // Icon size
            .padding(10)
            .background(Color.blue)
            .clipShape(Circle())
    }
}

enum TreatmentOption: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    case mealBolusCombo
    case meal
    case bolus

    var displayName: String {
        switch self {
        case .mealBolusCombo: return "Meal & Bolus"
        case .meal: return "Meal"
        case .bolus: return "Bolus"
        }
    }
}

struct PressableIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.clear)
            .opacity(configuration.isPressed ? 0.5 : 1.0) // Change opacity when pressed
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed) // Smooth transition
    }
}
