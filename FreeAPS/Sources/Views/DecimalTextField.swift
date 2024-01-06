import Combine
import SwiftUI

struct DecimalTextField: UIViewRepresentable {
    private var placeholder: String
    @Binding var value: Decimal
    private var formatter: NumberFormatter
    private var autofocus: Bool
    private var cleanInput: Bool
    private var useButtons: Bool

    init(
        _ placeholder: String,
        value: Binding<Decimal>,
        formatter: NumberFormatter,
        autofocus: Bool = false,
        cleanInput: Bool = false,
        useButtons: Bool = true
    ) {
        self.placeholder = placeholder
        _value = value
        self.formatter = formatter
        self.autofocus = autofocus
        self.cleanInput = cleanInput
        self.useButtons = useButtons
    }

    func makeUIView(context: Context) -> UITextField {
        let textfield = UITextField()
        textfield.keyboardType = .decimalPad
        textfield.delegate = context.coordinator
        textfield.placeholder = placeholder
        textfield.text = cleanInput ? "" : formatter.string(for: value) ?? placeholder
        textfield.textAlignment = .right

        lazy var toolBar: UIToolbar = {
            let tool: UIToolbar = .init(frame: .init(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 35))
            tool.barStyle = .default
            tool.isTranslucent = true
            tool.sizeToFit()

            let spaceArea: UIBarButtonItem = .init(systemItem: .flexibleSpace)
            let clearButton: UIBarButtonItem = .init(
                title: "Clear",
                style: .plain,
                target: self,
                action: #selector(textfield.clearButtonTapped(button:))
            )
            let doneButton: UIBarButtonItem = .init(
                title: "Done",
                style: .done,
                target: self,
                action: #selector(textfield.doneButtonTapped(button:))
            )
            tool.setItems([clearButton, spaceArea, doneButton], animated: false)
            tool.isUserInteractionEnabled = true

            return tool
        }()

        if useButtons {
            textfield.inputAccessoryView = toolBar
        }

        if autofocus {
            DispatchQueue.main.async {
                textfield.becomeFirstResponder()
            }
        }
        return textfield
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        let coordinator = context.coordinator
        if coordinator.isEditing {
            coordinator.resetEditing()
        } else if value == 0 {
            textField.text = ""
        } else {
            textField.text = formatter.string(for: value)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: DecimalTextField

        init(_ textField: DecimalTextField) {
            parent = textField
        }

        private(set) var isEditing = false
        private var editingCancellable: AnyCancellable?

        func resetEditing() {
            editingCancellable = Just(false)
                .delay(for: 0.5, scheduler: DispatchQueue.main)
                .weakAssign(to: \.isEditing, on: self)
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            // Allow only numbers and decimal characters
            let isNumber = CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: string))
            let withDecimal = (
                string == NumberFormatter().decimalSeparator &&
                    textField.text?.contains(string) == false
            )

            if isNumber || withDecimal,
               let currentValue = textField.text as NSString?
            {
                // Update Value
                let proposedValue = currentValue.replacingCharacters(in: range, with: string) as String

                let decimalFormatter = NumberFormatter()
                decimalFormatter.locale = Locale.current
                decimalFormatter.numberStyle = .decimal

                // Try currency formatter then Decimal formatrer
                let number = parent.formatter.number(from: proposedValue) ?? decimalFormatter.number(from: proposedValue) ?? 0.0

                // Set Value
                let double = number.doubleValue
                isEditing = true
                parent.value = Decimal(double)
            }

            return isNumber || withDecimal
        }

        func textFieldDidEndEditing(
            _ textField: UITextField,
            reason _: UITextField.DidEndEditingReason
        ) {
            // Format value with formatter at End Editing
            textField.text = parent.formatter.string(for: parent.value)
            isEditing = false
        }
    }
}

// MARK: extension for done button

extension UITextField {
    @objc func doneButtonTapped(button _: UIBarButtonItem) {
        resignFirstResponder()
    }

    @objc func clearButtonTapped(button _: UIBarButtonItem) {
        text = ""
    }
}

// MARK: extension for keyboard to dismiss

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
