import SwiftUI
import UIKit

public struct TextFieldWithToolBar: View {
    @Binding var text: Decimal
    var placeholder: String
    var textColor: Color
    var textAlignment: TextAlignment
    var keyboardType: UIKeyboardType
    var maxLength: Int?
    var maxValue: Decimal?
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
    // State flag to track if the field was intentionally cleared to zero
    @State private var isZeroCleared: Bool = false

    public init(
        text: Binding<Decimal>,
        placeholder: String,
        textColor: Color = .primary,
        textAlignment: TextAlignment = .trailing,
        keyboardType: UIKeyboardType = .decimalPad,
        maxLength: Int? = nil,
        maxValue: Decimal? = nil,
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
        self.maxValue = maxValue
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
                            isZeroCleared = true // Mark as cleared to prevent showing "0"
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
                    // When gaining focus: if the value is zero and was previously cleared,
                    // keep the text field empty to show placeholder instead of "0"
                    if isZeroCleared, text == 0 {
                        localText = ""
                    }
                } else {
                    // When losing focus: handle formatting and validation
                    if localText.isEmpty {
                        // If field is empty, maintain zero value but mark as cleared
                        // so we can show placeholder instead of "0"
                        text = 0
                        isZeroCleared = true
                    } else if let decimal = Decimal(string: localText, locale: numberFormatter.locale) {
                        if decimal != 0 {
                            // For non-zero values, format normally and update binding
                            text = decimal
                            localText = numberFormatter.string(from: decimal as NSNumber) ?? ""
                            isZeroCleared = false
                        } else {
                            // If user explicitly entered zero, store the value but
                            // keep display empty to show placeholder
                            text = 0
                            localText = ""
                            isZeroCleared = true
                        }
                    }
                }
            }
            .onChange(of: localText) { oldValue, newValue in
                // Reset zero-cleared state as soon as user starts typing anything
                if !newValue.isEmpty {
                    isZeroCleared = false
                }

                // Special handling for backspace operations to maintain decimal format
                if oldValue.count == newValue.count + 1 {
                    let decimalSeparator = numberFormatter.decimalSeparator ?? "."

                    // Special case: When backspacing to leave only a decimal point
                    // e.g., "10.1" -> "10." - Keep decimal separator without adding trailing zero
                    if newValue.hasSuffix(decimalSeparator) {
                        if let decimal = Decimal(string: newValue + "0", locale: numberFormatter.locale) {
                            text = decimal
                            textDidChange?(decimal)
                        }
                        return
                    }

                    // Special case: When backspacing the last digit after a decimal point
                    // e.g., "10.0" -> "10." - Ensure we keep proper decimal format
                    if oldValue.contains(decimalSeparator), newValue.contains(decimalSeparator) {
                        let oldParts = oldValue.components(separatedBy: decimalSeparator)
                        let newParts = newValue.components(separatedBy: decimalSeparator)

                        // Check if we've removed the last digit after decimal point
                        if oldParts.count > 1, newParts.count > 1,
                           oldParts[1].count == 1, newParts[1].isEmpty
                        {
                            // Keep proper decimal format by adding trailing zero
                            localText = newParts[0] + decimalSeparator + "0"

                            if let decimal = Decimal(string: localText, locale: numberFormatter.locale) {
                                text = decimal
                                textDidChange?(decimal)
                            }
                            return
                        }
                    }
                }

                // Process normal text input changes
                handleTextChange(oldValue, newValue)
            }
            .onChange(of: text) { oldValue, newValue in
                // Handle external changes to the text binding
                // (changes not initiated by typing, like programmatic changes)
                if oldValue != newValue,
                   Decimal(string: localText, locale: numberFormatter.locale) != newValue
                {
                    if newValue == 0, isZeroCleared {
                        // If value is zero and field was cleared, keep display empty to show placeholder
                        localText = ""
                    } else {
                        // Otherwise format and display the new value
                        localText = numberFormatter.string(from: newValue as NSNumber) ?? ""
                        isZeroCleared = false
                    }
                }
            }
            .onAppear {
                if text != 0 {
                    // Initialize with formatted non-zero value
                    localText = numberFormatter.string(from: text as NSNumber) ?? ""
                    isZeroCleared = false
                } else {
                    // For zero values, start with empty field to show placeholder
                    localText = ""
                    isZeroCleared = true
                }
                // Set initial focus if requested
                isFocused = initialFocus
            }
    }

    private func handleTextChange(_ oldValue: String, _ newValue: String) {
        // Handle empty input (clear operation)
        if newValue.isEmpty {
            text = 0
            isZeroCleared = true
            textDidChange?(0)
            return
        }

        // Remove leading zeros except for decimal values (e.g., "0.5")
        // This prevents inputs like "01", "0123", etc. but allows "0.5"
        if newValue.count > 1 && newValue.hasPrefix("0") && !newValue.hasPrefix("0" + (numberFormatter.decimalSeparator ?? ".")) {
            localText = String(newValue.dropFirst())
            return
        }

        let currentDecimalSeparator = numberFormatter.decimalSeparator ?? "."

        // Ensure there's only one decimal separator
        let decimalSeparatorCount = newValue.filter { String($0) == currentDecimalSeparator }.count
        if decimalSeparatorCount > 1 {
            // Reject input with multiple decimal separators
            localText = oldValue
            return
        }

        // Handle localization by converting to the correct decimal separator
        var processedText = newValue
        if newValue.contains("."), currentDecimalSeparator != "." {
            processedText = newValue.replacingOccurrences(of: ".", with: currentDecimalSeparator)
        } else if newValue.contains(","), currentDecimalSeparator != "," {
            processedText = newValue.replacingOccurrences(of: ",", with: currentDecimalSeparator)
        }

        // Automatically add leading zero when starting with decimal separator
        // For example ".5" becomes "0.5"
        if processedText.hasPrefix(currentDecimalSeparator) {
            processedText = "0" + processedText
        }

        // Validate against number formatter digit limits
        let components = processedText.components(separatedBy: currentDecimalSeparator)

        // Process the integer part (before decimal)
        var integerPart = components[0].filter { $0.isNumber }
        // Remove leading zeros for accurate digit counting
        while integerPart.hasPrefix("0") && integerPart.count > 1 {
            integerPart.removeFirst()
        }
        let integerDigits = integerPart.count

        // Count fraction digits (after decimal separator)
        let fractionDigits = components.count > 1 ? components[1].filter { $0.isNumber }.count : 0

        // Validate against the formatter's digit limits
        if integerDigits > numberFormatter.maximumIntegerDigits ||
            (allowDecimalSeparator && fractionDigits > numberFormatter.maximumFractionDigits)
        {
            // Reject input that exceeds digit limits
            localText = oldValue
            return
        }

        // Parse and validate the decimal value
        if let decimal = Decimal(string: processedText, locale: numberFormatter.locale) {
            if let maxValue = maxValue, decimal > maxValue {
                // Cap at maximum allowed value
                text = maxValue
                localText = numberFormatter.string(from: maxValue as NSNumber) ?? ""
                isZeroCleared = false
            } else {
                // Accept valid input and update binding
                text = decimal

                // Update zero-cleared state based on the value
                isZeroCleared = (decimal == 0) && localText.isEmpty

                textDidChange?(decimal)

                // If we had to process/modify the input, update the displayed text
                if processedText != newValue {
                    localText = processedText
                }
            }
        } else {
            // Reject invalid decimal inputs
            localText = oldValue
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
