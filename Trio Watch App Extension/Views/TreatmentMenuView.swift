import SwiftUI

struct TreatmentMenuView: View {
    @Environment(\.dismiss) var dismiss
    let deviceType: WatchSize
    @Binding var selectedTreatment: TreatmentOption?
    var onSelect: () -> Void // Callback to handle selection and dismiss the sheet

    // Define in array to achieve custom order of treatment options
    let treatments: [TreatmentOption] = [
        .meal, // First
        .bolus, // Second
        .mealBolusCombo // Third
    ]

    private var iconSize: CGFloat {
        switch deviceType {
        case .watch40mm,
             .watch41mm,
             .watch42mm:
            return 18
        case .unknown,
             .watch44mm,
             .watch45mm:
            return 22
        case .watch49mm:
            return 24
        }
    }

    private var iconPadding: CGFloat {
        switch deviceType {
        case .watch40mm,
             .watch41mm,
             .watch42mm:
            return 6
        case .unknown,
             .watch44mm,
             .watch45mm:
            return 10
        case .watch49mm:
            return 12
        }
    }

    var body: some View {
        VStack {
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
            .padding(iconPadding)
            .background(Color.orange)
            .clipShape(Circle())
    }

    var bolusIcon: some View {
        Image(systemName: "syringe.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: iconSize, height: iconSize)
            .padding(iconPadding)
            .background(Color.insulin)
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
        case .mealBolusCombo: return String(localized: "Meal & Bolus", comment: "Watch App Treatment Option 'Meal & Bolus'")
        case .meal: return String(localized: "Meal", comment: "Watch App Treatment Option 'Meal'")
        case .bolus: return String(localized: "Bolus", comment: "Watch App Treatment Option 'Bolus'")
        }
    }
}
