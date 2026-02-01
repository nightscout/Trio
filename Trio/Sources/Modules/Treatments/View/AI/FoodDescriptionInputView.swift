import SwiftUI

/// Inline view for adding an optional description before AI analysis.
/// Shown below the AI button after a photo is captured/selected.
struct FoodDescriptionInputView: View {
    @Binding var description: String
    let imageData: Data
    let onAnalyze: () -> Void
    let onCancel: () -> Void

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            // Photo thumbnail + description input
            HStack(alignment: .top, spacing: 12) {
                // Thumbnail
                if let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .cornerRadius(8)
                        .clipped()
                }

                // Description field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add context (optional)", comment: "Label for food description text field")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ZStack(alignment: .topLeading) {
                        if description.isEmpty {
                            Text("e.g., sugar-free, homemade…", comment: "Placeholder for food description")
                                .font(.subheadline)
                                .foregroundColor(Color(.placeholderText))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 8)
                        }
                        TextEditor(text: $description)
                            .font(.subheadline)
                            .frame(minHeight: 44, maxHeight: 64)
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                            .focused($isTextFieldFocused)
                    }
                    .background(Color(.systemGray6))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(.systemGray4), lineWidth: 0.5)
                    )
                }
            }

            // Example chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    exampleChip("No sugar added")
                    exampleChip("Homemade")
                    exampleChip("Large portion")
                    exampleChip("Low carb")
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel", comment: "Cancel description input")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onAnalyze) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.subheadline)
                        Text("Analyze", comment: "Button to analyze food with AI")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .cornerRadius(8)
                }
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
    }

    private func exampleChip(_ text: String) -> some View {
        Button(action: {
            if description.isEmpty {
                description = text.lowercased()
            } else {
                description += ", \(text.lowercased())"
            }
        }) {
            Text(text)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.secondarySystemFill))
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
    struct FoodDescriptionInputView_Previews: PreviewProvider {
        static var previews: some View {
            FoodDescriptionInputView(
                description: .constant(""),
                imageData: Data(),
                onAnalyze: {},
                onCancel: {}
            )
            .padding()
        }
    }
#endif
