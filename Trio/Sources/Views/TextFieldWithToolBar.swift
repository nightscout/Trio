import SwiftUI
import UIKit

public struct TextFieldWithToolBar: View {
    @Binding var text: Decimal
    var placeholder: String
    var textColor: Color
    var textAlignment: TextAlignment
    var keyboardType: UIKeyboardType
    var maxLength: Int?
    var isDismissible: Bool
    var textFieldDidBeginEditing: (() -> Void)?
    var textDidChange: ((Decimal) -> Void)?
    var numberFormatter: NumberFormatter
    var allowDecimalSeparator: Bool
    var showArrows: Bool
    var previousTextField: (() -> Void)?
    var nextTextField: (() -> Void)?
    var initialFocus: Bool

    @FocusState private var isFocused: Bool
    @State private var localText: String = ""

    public init(
        text: Binding<Decimal>,
        placeholder: String,
        textColor: Color = .primary,
        textAlignment: TextAlignment = .trailing,
        keyboardType: UIKeyboardType = .decimalPad,
        maxLength: Int? = nil,
        isDismissible: Bool = true,
        textFieldDidBeginEditing: (() -> Void)? = nil,
        textDidChange: ((Decimal) -> Void)? = nil,
        numberFormatter: NumberFormatter,
        allowDecimalSeparator: Bool = true,
        showArrows: Bool = false,
        previousTextField: (() -> Void)? = nil,
        nextTextField: (() -> Void)? = nil,
        initialFocus: Bool = false
    ) {
        _text = text
        self.placeholder = placeholder
        self.textColor = textColor
        self.textAlignment = textAlignment
        self.keyboardType = keyboardType
        self.maxLength = maxLength
        self.isDismissible = isDismissible
        self.textFieldDidBeginEditing = textFieldDidBeginEditing
        self.textDidChange = textDidChange
        self.numberFormatter = numberFormatter
        self.numberFormatter.numberStyle = .decimal
        self.allowDecimalSeparator = allowDecimalSeparator
        self.showArrows = showArrows
        self.previousTextField = previousTextField
        self.nextTextField = nextTextField
        self.initialFocus = initialFocus
    }

    public var body: some View {
        TextField(placeholder, text: $localText)
            .focused($isFocused)
            .multilineTextAlignment(textAlignment)
            .foregroundColor(textColor)
            .keyboardType(keyboardType)
            .toolbar {
                if isFocused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Button(action: {
                            localText = ""
                            text = 0
                            textDidChange?(0)
                        }) {
                            Image(systemName: "trash")
                        }

                        if showArrows {
                            Button(action: { previousTextField?() }) {
                                Image(systemName: "chevron.up")
                            }
                            Button(action: { nextTextField?() }) {
                                Image(systemName: "chevron.down")
                            }
                        }

                        Spacer()

                        if isDismissible {
                            Button(action: { isFocused = false }) {
                                Image(systemName: "keyboard.chevron.compact.down")
                            }
                        }
                    }
                }
            }
            .onChange(of: isFocused) { _, newValue in
                if newValue {
                    textFieldDidBeginEditing?()
                } else {
                    // Format when losing focus
                    if let decimal = Decimal(string: localText, locale: numberFormatter.locale) {
                        text = decimal
                        localText = numberFormatter.string(from: decimal as NSNumber) ?? ""
                    }
                }
            }
            .onChange(of: localText) { _, newValue in
                handleTextChange(newValue)
            }
//            .onChange(of: text) { _, newValue in
//                if newValue == 0, localText.isEmpty {
//                    // Keep empty state
//                    return
//                }
//                let newText = numberFormatter.string(from: newValue as NSNumber) ?? ""
//                if localText != newText {
//                    localText = newText
//                }
//            }
            .onAppear {
                if text != 0 {
                    localText = numberFormatter.string(from: text as NSNumber) ?? ""
                }
                // Set initial focus if requested
                isFocused = initialFocus
            }
    }

    private func handleTextChange(_ newValue: String) {
        // Handle empty string
        if newValue.isEmpty {
            text = 0
            textDidChange?(0)
            return
        }

        let currentDecimalSeparator = numberFormatter.decimalSeparator ?? "."

        // Prevent multiple decimal separators
        let decimalSeparatorCount = newValue.filter { String($0) == currentDecimalSeparator }.count
        if decimalSeparatorCount > 1 {
            // If there's already a decimal separator, prevent adding another one
            // by removing the last character (which would be the second decimal separator)
            localText = String(newValue.dropLast())
            return
        }

        // Replace wrong decimal separator with the correct one
        var processedText = newValue
        if newValue.contains("."), currentDecimalSeparator != "." {
            processedText = newValue.replacingOccurrences(of: ".", with: currentDecimalSeparator)
        } else if newValue.contains(","), currentDecimalSeparator != "," {
            processedText = newValue.replacingOccurrences(of: ",", with: currentDecimalSeparator)
        }

        // Handle leading decimal separator
        if processedText.hasPrefix(currentDecimalSeparator) {
            processedText = "0" + processedText
        }

        // Update if valid decimal
        if let decimal = Decimal(string: processedText, locale: numberFormatter.locale) {
            text = decimal
            textDidChange?(decimal)

            // If the processed text is different from the input, update the field
            if processedText != newValue {
                localText = processedText
            }
        } else {
            // If not a valid decimal, keep the old value
            localText = numberFormatter.string(from: text as NSNumber) ?? ""
        }
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
    @objc func endEditing() {
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
        textField.inputAccessoryView = isDismissible ? createToolbar(for: textField, context: context) : nil
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

    /// Creates and configures a toolbar for the text field with clear and dismiss buttons.
    /// - Parameters:
    ///   - textField: The text field for which the toolbar is being created.
    ///   - context: The SwiftUI context that contains the coordinator for handling button actions.
    /// - Returns: A configured UIToolbar with clear and dismiss buttons.
    private func createToolbar(for textField: UITextField, context: Context) -> UIToolbar {
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
        guard let currentText = textField.text as NSString? else {
            return false
        }

        // Calculate the new text length
        let newLength = currentText.length + string.count - range.length

        // If there's a maxLength, ensure the new length is within the limit
        if let maxLength = parent.maxLength, newLength > maxLength {
            return false
        }

        // Attempt to replace characters in range with the replacement string
        let newText = currentText.replacingCharacters(in: range, with: string)

        // Update the binding text state
        DispatchQueue.main.async {
            self.parent.text = newText
        }

        return true
    }
}
