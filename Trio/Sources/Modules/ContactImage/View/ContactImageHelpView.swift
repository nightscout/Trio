import SwiftUI

struct ContactImageHelpView: View {
    var state: ContactImage.StateModel
    var helpSheetDetent: Binding<PresentationDetent>

    var body: some View {
        NavigationStack {
            List {
                DefinitionRow(
                    term: String(localized: "How Trio Manages Contact Images"),
                    definition: Text(
                        "Trio will automatically assign a name like 'Trio 1' to any contact image you add, and a create an entry under your iOS Contacts. Use the 'Save' button at the bottom to save your customized contact image."
                    )
                ).listRowBackground(Color.gray.opacity(0.1))

                DefinitionRow(
                    term: String(localized: "Preview Contact Image"),
                    definition: Text(
                        "See a live preview of your contact image design at the top of the screen. Changes made to styles, layouts, or settings are instantly reflected."
                    )
                ).listRowBackground(Color.gray.opacity(0.1))

                DefinitionRow(term: String(localized: "Customize Layout and Style"), definition: VStack(alignment: .leading) {
                    Text("Choose from multiple layout options using the Layout Picker in the 'Style' section.")
                    Text("Enable High Contrast Mode for better visibility in certain conditions.")
                    Text("Available Layouts:")
                    Text("• Default: Single 'primary' value with up to two smaller values ('Top', 'Bottom') above and below it.")
                    Text("• Split: Divides values into two separate areas of same size.")
                }).listRowBackground(Color.gray.opacity(0.1))

                DefinitionRow(term: String(localized: "Set Display Values"), definition: VStack(alignment: .leading) {
                    Text("Select what values to show on the contact image (e.g., glucose, trend, none) for the available slots:")
                    Text("• None: No value displayed.")
                    Text("• Glucose Reading: Current CGM provided glucose value.")
                    Text("• Eventual Glucose: Glucose value as forecasted by the oref algorithm.")
                    Text("• Glucose Delta: Change in glucose value.")
                    Text("• Glucose Trend: Direction of glucose change.")
                    Text("• COB: Carbs on Board.")
                    Text("• IOB: Insulin on Board.")
                    Text("• Loop Status: Indicates current loop status (green, yellow, red).")
                    Text("• Last Loop Time: Time of the last algorithm run.")
                }).listRowBackground(Color.gray.opacity(0.1))

                DefinitionRow(term: String(localized: "Adjust Ring Settings"), definition: VStack(alignment: .leading) {
                    Text("Add visual Rings around the contact image to highlight information.")
                    Text("Fine-tune the ring’s Width and Gap to suit your design preferences.")
                    Text("Available Rings:")
                    Text("• Hidden: No ring displayed.")
                    Text("• Loop Status: Indicates current loop status (green, yellow, red).")
                }).listRowBackground(Color.gray.opacity(0.1))

                DefinitionRow(term: String(localized: "Customize Fonts"), definition: VStack(alignment: .leading) {
                    Text("Select font size, weight, and width to match your style:")
                    Text("• Font Size: Adjust the main text size.")
                    Text("• Secondary Font Size: Adjust text size for values in split layouts.")
                    Text("• Font Weight: Control how bold the text appears.")
                    Text("• Font Width: Choose between standard or expanded text spacing.")
                }).listRowBackground(Color.gray.opacity(0.1))
            }
            .scrollContentBackground(.hidden)
            .navigationBarTitle("Help", displayMode: .inline)

            Button { state.isHelpSheetPresented.toggle() }
            label: { Text("Got it!").bold().frame(maxWidth: .infinity, minHeight: 30, alignment: .center) }
                .buttonStyle(.bordered)
                .padding(.top)
        }
        .padding()
        .presentationDetents(
            [.fraction(0.9), .large],
            selection: helpSheetDetent
        )
    }
}
