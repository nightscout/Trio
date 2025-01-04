import SwiftUI

struct TreatmentMenuView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedTreatment: TreatmentOption?
    var onSelect: () -> Void // Callback to handle selection and dismiss the sheet

    // Define in array to achieve custom order of treatment options
    let treatments: [TreatmentOption] = [
        .meal, // First
        .bolus, // Second
        .mealBolusCombo // Third
    ]

    private var is40mm: Bool {
        let size = WKInterfaceDevice.current().screenBounds.size
        return size.height < 225 && size.width < 185
    }

    private var iconSize: CGFloat {
        is40mm ? 18 : 22
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(treatments) { treatment in
                    Button(action: {
                        selectedTreatment = treatment
                        onSelect()
                    }) {
                        HStack(spacing: 10) {
                            switch treatment {
                            case .meal:
                                mealIcon
                                Text(treatment.displayName)
                            case .bolus:
                                bolusIcon
                                Text(treatment.displayName)
                            case .mealBolusCombo:
                                mealIcon
                                bolusIcon
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PressableIconButtonStyle())
                }
            }.navigationTitle("Pick Treatment")
        }
    }

    var mealIcon: some View {
        Image(systemName: "fork.knife")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: iconSize, height: iconSize)
            .padding(is40mm ? 6 : 10)
            .background(Color.orange)
            .clipShape(Circle())
    }

    var bolusIcon: some View {
        Image(systemName: "syringe.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: iconSize, height: iconSize)
            .padding(is40mm ? 6 : 10)
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
            .opacity(configuration.isPressed ? 0.3 : 1.0) // Change opacity when pressed
            .animation(.easeInOut(duration: 0.25), value: configuration.isPressed) // Smooth transition
    }
}
