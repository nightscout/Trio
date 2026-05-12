import SwiftUI

/// Renders the exact payload that would be sent right now, with a copy button.
/// Linked to from Settings → App Diagnostics and from the migration sheet.
struct TelemetryPreviewView: View {
    @State private var jsonText: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "Below is the exact JSON object Trio would send right now. No glucose, insulin, carbs, credentials, or settings values are included."
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

                Text(jsonText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(6)

                Button {
                    UIPasteboard.general.string = jsonText
                } label: {
                    Label("Copy JSON", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle("What's sent")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { jsonText = Self.renderPayload() }
    }

    private static func renderPayload() -> String {
        let payload = TelemetryClient.shared.buildPayload()
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let text = String(data: data, encoding: .utf8)
        else {
            return String(localized: "Unable to render payload.")
        }
        return text
    }
}
