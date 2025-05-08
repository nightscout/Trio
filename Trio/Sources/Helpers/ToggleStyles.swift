import SwiftUI

struct RadioButtonToggleStyle: ToggleStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        HStack {
            Circle()
                .stroke(lineWidth: 2)
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
                .overlay {
                    if configuration.isOn {
                        Image(systemName: "circle.fill")
                    }
                }
                .onTapGesture {
                    withAnimation {
                        configuration.isOn.toggle()
                    }
                }
            configuration.label
        }
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    var tint = Color.primary

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 5)
                .stroke(lineWidth: 2)
                .foregroundColor(Color.secondary)
                .frame(width: 20, height: 20)
                .overlay {
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.body)
                            .fontWeight(.bold)
                            .foregroundColor(tint)
                    }
                }
                .onTapGesture {
                    configuration.isOn.toggle()
                }

            configuration.label
        }
        .contentShape(Rectangle()) // make entire HStack tappable
        .onTapGesture {
            configuration.isOn.toggle()
        }
    }
}
