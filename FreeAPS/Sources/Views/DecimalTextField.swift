import Combine
import Foundation
import SwiftUI

struct DecimalTextField: UIViewRepresentable {
    private var placeholder: String
    @Binding var value: Decimal
    private var formatter: NumberFormatter
    private var autofocus: Bool
    private var cleanInput: Bool

    init(
        _ placeholder: String,
        value: Binding<Decimal>,
        formatter: NumberFormatter,
        autofocus: Bool = false,
        cleanInput: Bool = false
    ) {
        self.placeholder = placeholder
        _value = value
        self.formatter = formatter
        self.autofocus = autofocus
        self.cleanInput = cleanInput
    }

    func makeUIView(context: Context) -> UITextField {
        let textfield = UITextField()
        textfield.keyboardType = .decimalPad
        textfield.delegate = context.coordinator
        textfield.placeholder = placeholder
        textfield.text = cleanInput ? "" : formatter.string(for: value) ?? placeholder
        textfield.textAlignment = .right

        let toolBar = UIToolbar(frame: CGRect(
            x: 0,
            y: 0,
            width: textfield.frame.size.width,
            height: 44
        ))
        let clearButton = UIBarButtonItem(
            title: NSLocalizedString("Clear", comment: "Clear button"),
            style: .plain,
            target: self,
            action: #selector(textfield.clearButtonTapped(button:))
        )
        let doneButton = UIBarButtonItem(
            title: NSLocalizedString("Done", comment: "Done button"),
            style: .done,
            target: self,
            action: #selector(textfield.doneButtonTapped(button:))
        )
        let space = UIBarButtonItem(
            barButtonSystemItem: UIBarButtonItem.SystemItem.flexibleSpace,
            target: nil,
            action: nil
        )
        toolBar.setItems([clearButton, space, doneButton], animated: true)
        textfield.inputAccessoryView = toolBar
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
        private(set) var _beganEditing = false
        private(set) var _rightAlign = true
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
            if textField.text == "0"
            {
                textField.text = ""
            }
            isEditing = false
            NotificationBroadcaster.shared.removeListeners(for: "ClearButtonTappedObserver")
        }

        func textFieldDidBeginEditing(_: UITextField) {
            _beganEditing =
                true // if we change cursor position here (with DispatchQueue), cursor jumps ; instead, do in DidChangeSelection
            NotificationBroadcaster.shared.register(event: "ClearButtonTappedObserver") { [self] _ in
                clearButtonTappedDidUpdate(object: self)
            }
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            if _beganEditing {
                _beganEditing = false
                if _rightAlign {
                    let position = textField.endOfDocument
                    textField.selectedTextRange = textField.textRange(from: position, to: position)
                }
            }
        }

        func clearButtonTappedDidUpdate(object _: Any) {
            parent.value = 0
        }
    }
}

// MARK: Singleton NotificationBroadcaster class

class NotificationBroadcaster {
    static let shared = NotificationBroadcaster()

    private var listeners: [String: [(Any) -> Void]] = [:]

    func register(event: String, listener: @escaping (Any) -> Void) {
        if listeners[event] == nil {
            listeners[event] = []
        }
        listeners[event]?.append(listener)
    }

    func notify(event: String, object: Any?) {
        listeners[event]?.forEach { $0(object ?? ()) }
    }

    func removeListeners(for event: String) {
        listeners[event] = nil
    }
}

// MARK: extension for done button

extension UITextField {
    private var broadcaster: NotificationBroadcaster {
        NotificationBroadcaster.shared
    }

    @objc func doneButtonTapped(button _: UIBarButtonItem) {
        resignFirstResponder()
    }

    @objc func clearButtonTapped(button _: UIBarButtonItem) {
        text = ""
        broadcaster.notify(event: "ClearButtonTappedObserver", object: self)
    }
}

// MARK: extension for keyboard to dismiss

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: RightAdjustedTextField UITextField implementation

struct RightAdjustedTextField: UIViewRepresentable {
    @Binding var text: String
    var textAlignment: NSTextAlignment

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: RightAdjustedTextField

        init(parent: RightAdjustedTextField) {
            self.parent = parent
        }

        // Position cursor at end of text
        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                let endPosition = textField.endOfDocument
                textField.selectedTextRange = textField.textRange(from: endPosition, to: endPosition)
            }
            NotificationBroadcaster.shared.register(event: "ClearButtonTappedObserver") { [self] _ in
                clearButtonTappedDidUpdate(object: self)
            }
        }

        func textFieldDidEndEditing(
            _ textField: UITextField,
            reason _: UITextField.DidEndEditingReason
        ) {
            textField.text = parent.text
            NotificationBroadcaster.shared.removeListeners(for: "ClearButtonTappedObserver")
        }

        func clearButtonTappedDidUpdate(object _: Any) {
            parent.text = ""
        }

        @objc func textFieldEditingChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.textAlignment = textAlignment
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textFieldEditingChanged(_:)), for: .editingChanged)
        let toolBar = UIToolbar(frame: CGRect(
            x: 0,
            y: 0,
            width: textField.frame.size.width,
            height: 44
        ))
        let clearButton = UIBarButtonItem(
            title: NSLocalizedString("Clear", comment: "Clear button"),
            style: .plain,
            target: self,
            action: #selector(textField.clearButtonTapped(button:))
        )
        let doneButton = UIBarButtonItem(
            title: NSLocalizedString("Done", comment: "Done button"),
            style: .done,
            target: self,
            action: #selector(textField.doneButtonTapped(button:))
        )
        let space = UIBarButtonItem(
            barButtonSystemItem: UIBarButtonItem.SystemItem.flexibleSpace,
            target: nil,
            action: nil
        )
        toolBar.setItems([clearButton, space, doneButton], animated: true)
        textField.inputAccessoryView = toolBar
        return textField
    }

    func updateUIView(_ uiView: UITextField, context _: Context) {
        uiView.text = text
        uiView.textAlignment = textAlignment
    }
}
