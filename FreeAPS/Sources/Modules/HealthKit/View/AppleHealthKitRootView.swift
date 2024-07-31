import SwiftUI
import Swinject

extension AppleHealthKit {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: String?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        @Environment(\.colorScheme) var colorScheme
        var color: LinearGradient {
            colorScheme == .dark ? LinearGradient(
                gradient: Gradient(colors: [
                    Color.bgDarkBlue,
                    Color.bgDarkerDarkBlue
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
                :
                LinearGradient(
                    gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
        }

        var body: some View {
            Form {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.useAppleHealth,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = "Connect to Apple Health"
                        }
                    ),
                    type: .boolean,
                    label: "Connect to Apple Health",
                    miniHint: "Allows Trio to read from and write to Apple Health.",
                    verboseHint: NSLocalizedString(
                        "This allows Trio to read from and write to Apple Health. You must also give permissions in iOS Settings > Health > Data Access. If you enter a glucose value into Apple Health, open Trio to confirm it shows up.",
                        comment: "Suspend Zeros IOB"
                    ),
                    headerText: "Apple Health Integration"
                )

                if !state.needShowInformationTextForSetPermissions {
                    Section {
                        VStack {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text("Give Apple Health Write Permissions")
                            }.padding(.bottom)
                            Text("""
                            1. Open the Settings app on your iOS device.
                            2. Scroll down and select "Health."
                            3. Tap on "Data Access & Devices."
                            4. Find and select "Trio" from the list of apps.
                            5. Ensure that the "Write Data" option is enabled for the desired health metrics.
                            """).font(.footnote)
                        }
                        .padding(.vertical)
                        .foregroundColor(Color.secondary)
                    }.listRowBackground(Color.chart)
                }
            }
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? "",
                    sheetTitle: "Help"
                )
            }
            .scrollContentBackground(.hidden).background(color)
            .onAppear(perform: configureView)
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
