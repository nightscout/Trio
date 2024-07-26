import SwiftUI
import UIKit

public struct TextFieldWithToolBar: UIViewRepresentable {
    @Binding var text: Decimal
    var placeholder: String
    var textColor: UIColor
    var textAlignment: NSTextAlignment
    var keyboardType: UIKeyboardType
    var autocapitalizationType: UITextAutocapitalizationType
    var autocorrectionType: UITextAutocorrectionType
    var shouldBecomeFirstResponder: Bool
    var maxLength: Int?
    var isDismissible: Bool
    var textFieldDidBeginEditing: (() -> Void)?
    var numberFormatter: NumberFormatter
    var allowDecimalSeparator: Bool

    public init(
        text: Binding<Decimal>,
        placeholder: String,
        textColor: UIColor = .label,
        textAlignment: NSTextAlignment = .right,
        keyboardType: UIKeyboardType = .decimalPad,
        autocapitalizationType: UITextAutocapitalizationType = .none,
        autocorrectionType: UITextAutocorrectionType = .no,
        shouldBecomeFirstResponder: Bool = false,
        maxLength: Int? = nil,
        isDismissible: Bool = true,
        textFieldDidBeginEditing: (() -> Void)? = nil,
        numberFormatter: NumberFormatter,
        allowDecimalSeparator: Bool = true
    ) {
        _text = text
        self.placeholder = placeholder
        self.textColor = textColor
        self.textAlignment = textAlignment
        self.keyboardType = keyboardType
        self.autocapitalizationType = autocapitalizationType
        self.autocorrectionType = autocorrectionType
        self.shouldBecomeFirstResponder = shouldBecomeFirstResponder
        self.maxLength = maxLength
        self.isDismissible = isDismissible
        self.textFieldDidBeginEditing = textFieldDidBeginEditing
        self.numberFormatter = numberFormatter
        self.numberFormatter.numberStyle = .decimal
        self.allowDecimalSeparator = allowDecimalSeparator
    }

    public func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        context.coordinator.textField = textField
        textField.inputAccessoryView = isDismissible ? makeDoneToolbar(for: textField, context: context) : nil
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingDidBegin), for: .editingDidBegin)
        textField.delegate = context.coordinator
        if text == 0 { /// show no value initially, i.e. empty String
            textField.text = ""
        } else {
            textField.text = numberFormatter.string(for: text)
        }
        textField.placeholder = placeholder
        return textField
    }

    private func makeDoneToolbar(for textField: UITextField, context: Context) -> UIToolbar {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 50))
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            style: .done,
            target: textField,
            action: #selector(UITextField.resignFirstResponder)
        )
        let clearButton = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.clearText)
        )

        toolbar.items = [clearButton, flexibleSpace, doneButton]
        toolbar.sizeToFit()
        return toolbar
    }

    public func updateUIView(_ textField: UITextField, context: Context) {
        if text != 0 {
            let newText = numberFormatter.string(for: text) ?? ""
            if textField.text != newText {
                textField.text = newText
            }
        }

        textField.textColor = textColor
        textField.textAlignment = textAlignment
        textField.keyboardType = keyboardType
        textField.autocapitalizationType = autocapitalizationType
        textField.autocorrectionType = autocorrectionType

        if shouldBecomeFirstResponder, !context.coordinator.didBecomeFirstResponder {
            if textField.window != nil, textField.becomeFirstResponder() {
                context.coordinator.didBecomeFirstResponder = true
            }
        } else if !shouldBecomeFirstResponder, context.coordinator.didBecomeFirstResponder {
            context.coordinator.didBecomeFirstResponder = false
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self, maxLength: maxLength)
    }

    public final class Coordinator: NSObject {
        var parent: TextFieldWithToolBar
        var textField: UITextField?
        let maxLength: Int?
        var didBecomeFirstResponder = false
        let decimalFormatter: NumberFormatter

        init(_ parent: TextFieldWithToolBar, maxLength: Int?) {
            self.parent = parent
            self.maxLength = maxLength
            decimalFormatter = NumberFormatter()
            decimalFormatter.locale = Locale.current
            decimalFormatter.numberStyle = .decimal
        }

        @objc fileprivate func clearText() {
            parent.text = 0
            textField?.text = ""
        }

        @objc fileprivate func editingDidBegin(_ textField: UITextField) {
            DispatchQueue.main.async {
                textField.moveCursorToEnd()
            }
        }
    }
}

extension TextFieldWithToolBar.Coordinator: UITextFieldDelegate {
    public func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        // Check if the input is a number or the decimal separator
        let isNumber = CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: string))
        let isDecimalSeparator = (string == decimalFormatter.decimalSeparator && textField.text?.contains(string) == false)
        var allowChange = true

        // Only proceed if the input is a valid number or decimal separator
        if isNumber || isDecimalSeparator && parent.allowDecimalSeparator,
           let currentText = textField.text as NSString?
        {
            // Get the proposed new text
            let proposedTextOriginal = currentText.replacingCharacters(in: range, with: string)

            // Remove thousand separator
            let proposedText = proposedTextOriginal.replacingOccurrences(of: decimalFormatter.groupingSeparator, with: "")

            let number = parent.numberFormatter.number(from: proposedText) ?? decimalFormatter.number(from: proposedText)

            // Update the binding value if conversion is successful
            if let number = number {
                let lastCharIndex = proposedText.index(before: proposedText.endIndex)
                let hasDecimalSeparator = proposedText.contains(decimalFormatter.decimalSeparator)
                let hasTrailingZeros = (
                    parent.numberFormatter
                        .maximumFractionDigits > 0 && hasDecimalSeparator && proposedText[lastCharIndex] == "0"
                ) ||
                    (isDecimalSeparator && parent.numberFormatter.allowsFloats)
                if !parent.numberFormatter.allowsFloats || !hasTrailingZeros
                {
                    parent.text = number.decimalValue
                }
                if parent.numberFormatter.allowsFloats, hasDecimalSeparator {
                    let rangeOfDecimal = proposedText.range(of: decimalFormatter.decimalSeparator)
                    let decimalIndexInt: Int = proposedText.distance(
                        from: proposedText.startIndex,
                        to: rangeOfDecimal!.lowerBound
                    )
                    let maxDigits = decimalIndexInt + parent.numberFormatter.maximumFractionDigits + 1
                    allowChange = proposedText.count > maxDigits ? false : true
                }
            } else {
                parent.text = 0
            }
        }

        // Allow the change if it's a valid number or decimal separator
        return isNumber && allowChange || isDecimalSeparator && parent.allowDecimalSeparator && parent.numberFormatter
            .allowsFloats
    }

    public func textFieldDidBeginEditing(_: UITextField) {
        parent.textFieldDidBeginEditing?()
    }
}

extension UITextField {
    func moveCursorToEnd() {
        dispatchPrecondition(condition: .onQueue(.main))
        let newPosition = endOfDocument
        selectedTextRange = textRange(from: newPosition, to: newPosition)
    }
}

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

public struct TextFieldWithToolBarString: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var textAlignment: NSTextAlignment = .right
    var keyboardType: UIKeyboardType = .default
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var autocorrectionType: UITextAutocorrectionType = .no
    var shouldBecomeFirstResponder: Bool = false
    var maxLength: Int? = nil
    var isDismissible: Bool = true

    public func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        context.coordinator.textField = textField
        textField.inputAccessoryView = isDismissible ? makeDoneToolbar(for: textField, context: context) : nil
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingDidBegin), for: .editingDidBegin)
        textField.delegate = context.coordinator
        textField.text = text
        textField.placeholder = placeholder
        textField.textAlignment = textAlignment
        textField.keyboardType = keyboardType
        textField.autocapitalizationType = autocapitalizationType
        textField.autocorrectionType = autocorrectionType
        textField.adjustsFontSizeToFitWidth = true
        return textField
    }

    private func makeDoneToolbar(for textField: UITextField, context: Context) -> UIToolbar {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 50))
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            style: .done,
            target: textField,
            action: #selector(UITextField.resignFirstResponder)
        )
        let clearButton = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.clearText)
        )

        toolbar.items = [clearButton, flexibleSpace, doneButton]
        toolbar.sizeToFit()
        return toolbar
    }

    public func updateUIView(_ textField: UITextField, context: Context) {
        if textField.text != text {
            textField.text = text
        }

        textField.textAlignment = textAlignment
        textField.keyboardType = keyboardType
        textField.autocapitalizationType = autocapitalizationType
        textField.autocorrectionType = autocorrectionType

        if shouldBecomeFirstResponder, !context.coordinator.didBecomeFirstResponder {
            if textField.window != nil, textField.becomeFirstResponder() {
                context.coordinator.didBecomeFirstResponder = true
            }
        } else if !shouldBecomeFirstResponder, context.coordinator.didBecomeFirstResponder {
            context.coordinator.didBecomeFirstResponder = false
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self, maxLength: maxLength)
    }

    public final class Coordinator: NSObject {
        var parent: TextFieldWithToolBarString
        var textField: UITextField?
        let maxLength: Int?
        var didBecomeFirstResponder = false

        init(_ parent: TextFieldWithToolBarString, maxLength: Int?) {
            self.parent = parent
            self.maxLength = maxLength
        }

        @objc fileprivate func clearText() {
            parent.text = ""
            textField?.text = ""
        }

        @objc fileprivate func editingDidBegin(_ textField: UITextField) {
            DispatchQueue.main.async {
                textField.moveCursorToEnd()
            }
        }
    }
}

extension TextFieldWithToolBarString.Coordinator: UITextFieldDelegate {
    public func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        if let maxLength = parent.maxLength {
            // Get the current text, including the proposed change
            let currentText = textField.text ?? ""
            let newLength = currentText.count + string.count - range.length
            if newLength > maxLength {
                return false
            }
        }

        DispatchQueue.main.async {
            if let textFieldText = textField.text as NSString? {
                let newText = textFieldText.replacingCharacters(in: range, with: string)
                self.parent.text = newText
            }
        }

        return true
    }
}
