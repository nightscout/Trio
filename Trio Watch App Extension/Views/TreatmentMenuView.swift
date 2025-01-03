import SwiftUI

struct TreatmentMenuView: View {
    @Environment(\.presentationMode) var presentationMode
    let treatments = TreatmentOptions.allCases
    @State private var selectedOption: TreatmentOptions? = nil

    var body: some View {
        ScrollView {
            HStack {
                Spacer()
                Text("Choose Treatment:")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
            }

            // Options list
            VStack(spacing: 10) {
                ForEach(treatments) { treatment in
                    Button(action: {
                        selectedOption = treatment
                        presentationMode.wrappedValue.dismiss() // Close after selecting
                    }) {
                        HStack(alignment: .center, spacing: 8) {
                            switch treatment {
                            case .mealBolusCombo:
                                // First Icon
                                HStack(spacing: 0) {
                                    Image(systemName: "fork.knife")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 22, height: 22) // Icon size
                                        .padding(10) // Padding inside the circle
                                        .background(Color.orange) // Circle background color
                                        .clipShape(Circle())

                                    // Plus Icon
                                    Image(systemName: "plus")
                                        .font(.caption)
                                        .bold()
                                        .frame(width: 24, height: 24) // Ensures consistent sizing

                                    // Second Icon
                                    Image(systemName: "syringe.fill")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 22, height: 22) // Icon size
                                        .padding(10)
                                        .background(Color.blue)
                                        .clipShape(Circle())
                                }
                            case .meal:
                                Image(systemName: "fork.knife")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 22, height: 22) // Icon size
                                    .padding(10)
                                    .background(Color.orange)
                                    .clipShape(Circle())

                            case .bolus:
                                Image(systemName: "syringe.fill")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 22, height: 22) // Icon size
                                    .padding(10)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PressableIconButtonStyle())
                }
            }
            .padding(.horizontal)
            .background(Color.clear)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

enum TreatmentOptions: String, CaseIterable, Identifiable {
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
            .opacity(configuration.isPressed ? 0.6 : 1.0) // Change opacity when pressed
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed) // Smooth transition
    }
}
