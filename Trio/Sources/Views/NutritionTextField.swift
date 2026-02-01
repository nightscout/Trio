import SwiftUI
import UIKit

// MARK: - Nutrition Text Field

/// A reusable text field for editing nutrition values (carbs, fat, protein, etc.)
/// with built-in keyboard toolbar and decimal separator handling.
/// Uses UIKit internally to ensure toolbar visibility.
public struct NutritionTextField<Field: Hashable>: View {
    let label: String
    @Binding var value: Double
    let unit: String
    let field: Field
    var focusedField: FocusState<Field?>.Binding

    let numberFormatter: NumberFormatter

    public init(
        label: String,
        value: Binding<Double>,
        unit: String = "g",
        field: Field,
        focusedField: FocusState<Field?>.Binding,
        numberFormatter: NumberFormatter? = nil
    ) {
        self.label = label
        _value = value
        self.unit = unit
        self.field = field
        self.focusedField = focusedField

        if let formatter = numberFormatter {
            self.numberFormatter = formatter
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            formatter.locale = Locale.current
            self.numberFormatter = formatter
        }
    }

    public var body: some View {
        let isFocused = focusedField.wrappedValue == field
        ZStack {
            KeyboardToolbarTextField(
                value: $value,
                formatter: numberFormatter,
                configuration: .init(
                    keyboardType: .decimalPad,
                    textAlignment: .right,
                    placeholder: "0"
                ),
                onFocusContext: { isFocused in
                    if isFocused {
                        focusedField.wrappedValue = field
                    } else if focusedField.wrappedValue == field {
                        focusedField.wrappedValue = nil
                    }
                },
                externalFocus: isFocused
            )
            .padding(.horizontal)
            .padding(.trailing, 25) // Extra padding to avoid overlapping with unit
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)

            // Overlays: label (left) and unit (right) — don't intercept taps
            HStack {
                Text(label)
                    .foregroundStyle(isFocused ? .primary : .secondary)
                    .font(.subheadline.weight(isFocused ? .semibold : .regular))
                    .allowsHitTesting(false)
                Spacer()
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .trailing)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(isFocused ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField.wrappedValue = field
        }
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Amount Text Field

/// A reusable text field for entering amounts (weight/volume) with unit toggle.
public struct AmountTextField<Field: Hashable>: View {
    @Binding var amount: Double
    @Binding var isMl: Bool
    let field: Field
    var focusedField: FocusState<Field?>.Binding

    let numberFormatter: NumberFormatter

    public init(
        amount: Binding<Double>,
        isMl: Binding<Bool>,
        field: Field,
        focusedField: FocusState<Field?>.Binding,
        numberFormatter: NumberFormatter? = nil
    ) {
        _amount = amount
        _isMl = isMl
        self.field = field
        self.focusedField = focusedField

        if let formatter = numberFormatter {
            self.numberFormatter = formatter
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            formatter.locale = Locale.current
            self.numberFormatter = formatter
        }
    }

    public var body: some View {
        let isFocused = focusedField.wrappedValue == field

        HStack(spacing: 12) {
            HStack(spacing: 4) {
                KeyboardToolbarTextField(
                    value: $amount,
                    formatter: numberFormatter,
                    configuration: .init(
                        keyboardType: .decimalPad,
                        textAlignment: .right,
                        placeholder: "0",
                        font: .systemFont(ofSize: 22, weight: .semibold)
                    ),
                    onFocusContext: { isFocused in
                        if isFocused {
                            focusedField.wrappedValue = field
                        } else if focusedField.wrappedValue == field {
                            focusedField.wrappedValue = nil
                        }
                    },
                    externalFocus: isFocused
                )
                .frame(minWidth: 110, maxWidth: 140)

                Text(isMl ? "ml" : "g")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Unit toggle
            Picker("Unit", selection: $isMl) {
                Text("g").tag(false)
                Text("ml").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
        }
    }
}

// MARK: - Internal UIKit Implementation

public struct KeyboardToolbarTextField: UIViewRepresentable {
    @Binding var value: Double
    public let formatter: NumberFormatter
    public let configuration: Configuration
    public let onFocusContext: (Bool) -> Void
    public let externalFocus: Bool

    public struct Configuration {
        public var keyboardType: UIKeyboardType = .decimalPad
        public var textAlignment: NSTextAlignment = .right
        public var placeholder: String = ""
        public var font: UIFont?
        public var textColor: UIColor = .label

        public init(
            keyboardType: UIKeyboardType = .decimalPad,
            textAlignment: NSTextAlignment = .right,
            placeholder: String = "",
            font: UIFont? = nil,
            textColor: UIColor = .label
        ) {
            self.keyboardType = keyboardType
            self.textAlignment = textAlignment
            self.placeholder = placeholder
            self.font = font
            self.textColor = textColor
        }
    }

    public init(
        value: Binding<Double>,
        formatter: NumberFormatter,
        configuration: Configuration = .init(),
        onFocusContext: @escaping (Bool) -> Void = { _ in },
        externalFocus: Bool = false
    ) {
        _value = value
        self.formatter = formatter
        self.configuration = configuration
        self.onFocusContext = onFocusContext
        self.externalFocus = externalFocus
    }

    public func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.keyboardType = configuration.keyboardType
        textField.textAlignment = configuration.textAlignment
        textField.placeholder = configuration.placeholder
        if let font = configuration.font {
            textField.font = font
        }
        textField.textColor = configuration.textColor

        // Setup Toolbar
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 50))
        toolbar.items = [
            UIBarButtonItem(
                image: UIImage(systemName: "trash"),
                style: .plain,
                target: context.coordinator,
                action: #selector(Coordinator.clearText)
            ),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(
                image: UIImage(systemName: "keyboard.chevron.compact.down"),
                style: .done,
                target: textField,
                action: #selector(UITextField.resignFirstResponder)
            )
        ]
        toolbar.sizeToFit()
        textField.inputAccessoryView = toolbar
        context.coordinator.textField = textField

        return textField
    }

    public func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        // Clear entering focus flag if we have achieved consistency
        if externalFocus {
            context.coordinator.isEnteringFocus = false
        }

        // Sync value to text only if not currently editing (to avoid cursor jumping/formatting issues while typing)
        // OR if the value changed externally significantly
        if !uiView.isEditing {
            updateTextField(uiView)
        }

        // External focus handling
        if externalFocus && !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        } else if !externalFocus, uiView.isFirstResponder {
            // Only force resign if we are NOT in the middle of entering focus
            // This prevents race conditions where parent view updates (e.g. keyboard safe area)
            // trigger updateUIView before the binding has propagated the focus state.
            if !context.coordinator.isEnteringFocus {
                DispatchQueue.main.async {
                    uiView.resignFirstResponder()
                }
            }
        }
    }

    private func updateTextField(_ textField: UITextField) {
        if value == 0 {
            textField.text = ""
        } else {
            textField.text = formatter.string(from: NSNumber(value: value))
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, UITextFieldDelegate {
        var parent: KeyboardToolbarTextField
        weak var textField: UITextField?
        var isEnteringFocus = false

        init(_ parent: KeyboardToolbarTextField) {
            self.parent = parent
        }

        @objc func clearText() {
            parent.value = 0
            textField?.text = ""
        }

        public func textFieldShouldBeginEditing(_: UITextField) -> Bool {
            isEnteringFocus = true
            return true
        }

        public func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onFocusContext(true)
            // Move cursor to end of document
            DispatchQueue.main.async {
                let newPosition = textField.endOfDocument
                textField.selectedTextRange = textField.textRange(from: newPosition, to: newPosition)
            }
        }

        public func textFieldDidEndEditing(_ textField: UITextField) {
            isEnteringFocus = false
            parent.onFocusContext(false)
            // Final format on end editing
            parent.updateTextField(textField)
        }

        public func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            guard let currentText = textField.text as NSString? else { return true }
            let newText = currentText.replacingCharacters(in: range, with: string)

            // Allow empty (clearing)
            if newText.isEmpty {
                parent.value = 0
                return true
            }

            // Normalize decimal separator
            let localeSeparator = parent.formatter.decimalSeparator ?? "."
            var paramText = newText

            // Replace common separators with locale specific one
            if localeSeparator == "." {
                paramText = paramText.replacingOccurrences(of: ",", with: ".")
            } else if localeSeparator == "," {
                paramText = paramText.replacingOccurrences(of: ".", with: ",")
            }

            // Check if it's a valid number format (allow partial inputs like "0.")
            // Direct Double conversion might fail for "0." so we handle it manually

            // Special case: just decimal separator -> "0."
            if paramText == localeSeparator {
                // We don't update binding yet, or update to 0, but allow text change
                return true
            }

            // Validate if valid decimal number
            // Using NumberFormatter to parse is safer for locale support
            if parent.formatter.number(from: paramText) != nil {
                // Update binding
                // We need to convert back to Double.
                // NOTE: NSNumber(value: double) -> string uses formatter
                // Here we want string -> double
                if let num = parent.formatter.number(from: paramText) {
                    parent.value = num.doubleValue
                }
                return true
            } else if paramText.hasSuffix(localeSeparator) {
                // Allow typing the separator even if number(from:) returns nil (sometimes)
                // But check if prefix is number
                let prefix = String(paramText.dropLast())
                if parent.formatter.number(from: prefix) != nil || prefix.isEmpty {
                    return true
                }
            }

            return false
        }
    }
}
