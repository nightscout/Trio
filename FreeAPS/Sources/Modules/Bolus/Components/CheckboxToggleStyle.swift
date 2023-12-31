import SwiftUI

struct CheckboxToggleStyle: ToggleStyle {
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
