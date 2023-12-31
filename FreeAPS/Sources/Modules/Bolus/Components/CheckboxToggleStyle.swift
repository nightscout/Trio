import SwiftUI

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 5)
                .stroke(lineWidth: 2)
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
                .overlay {
                    if configuration.isOn {
                        Image(systemName: "checkmark")
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

import SwiftUI

struct CheckboxToggleStyleVariant: ToggleStyle {
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
