import SwiftUI

extension BarcodeScanner {
    /// A reusable search text field component
    struct ProductSearchField: View {
        @Binding var searchText: String
        var isFocused: FocusState<Bool>.Binding
        var onSubmit: () -> Void
        var onClear: () -> Void
        var onChange: () -> Void

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Search foods..."), text: $searchText)
                    .focused(isFocused)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit(onSubmit)
                    .toolbar {
                        if isFocused.wrappedValue {
                            ToolbarItemGroup(placement: .keyboard) {
                                Button(action: {
                                    searchText = ""
                                }) {
                                    Image(systemName: "trash")
                                }
                                Spacer()
                                Button(action: {
                                    isFocused.wrappedValue = false
                                }) {
                                    Image(systemName: "keyboard.chevron.compact.down")
                                }
                            }
                        }
                    }
                    .onChange(of: searchText) { _, _ in
                        onChange()
                    }

                if !searchText.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
