import SwiftUI

struct StatExportMenuInfoView: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(String(
                    localized: """
                    1. Select a date range.

                    2. Select a data type and chart type, and tap "Add to Report".

                    3. Repeat step 2 until you get all the information you want into the report.

                    4. Add a Patient Name (optional) and tap Export.

                    5. For easier exports, save your selection as a Preset by tapping "Save as Preset…".
                    """,
                    comment: "Info sheet body explaining how to build and export a Statistics PDF report"
                ))
                    .padding()
            }
            .navigationTitle(String(
                localized: "About PDF Export",
                comment: "Info sheet title for the Statistics PDF export feature"
            ))
            .navigationBarTitleDisplayMode(.inline)

            Button {
                isPresented = false
            } label: {
                Text("Got it!", comment: "Dismiss button for the PDF export info sheet")
                    .bold()
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
            }
            .buttonStyle(.bordered)
            .padding([.horizontal, .bottom])
            .padding(.top, 4)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
