import SwiftUI

struct WatchConfigGarminAppConfigView: View {
    @ObservedObject var state: WatchConfig.StateModel

    @State private var shouldDisplayHint1: Bool = false
    @State private var shouldDisplayHint2: Bool = false
    @State private var shouldDisplayHint3: Bool = false
    @State private var shouldDisplayHint4: Bool = false
    @State var hintDetent = PresentationDetent.large
    @State private var shouldShowWatchfaceSwitchConfirmDialog: Bool = false

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        Form {
            // MARK: - Watchface Selection Section

            Section(
                header: Text("Watchface Settings"),
                content: {
                    VStack {
                        Picker(
                            selection: $state.garminSettings.watchface,
                            label: Text("Watchface Selection").multilineTextAlignment(.leading)
                        ) {
                            ForEach(GarminWatchface.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }
                        .padding(.top)
                        .onChange(of: state.garminSettings.watchface) { oldValue, newValue in
                            if oldValue != newValue {
                                state.handleWatchfaceChange()
                                shouldShowWatchfaceSwitchConfirmDialog = true
                            }
                        }

                        HStack(alignment: .center) {
                            Text(
                                "Choose which watchface to support."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    shouldDisplayHint1.toggle()
                                },
                                label: {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.top)
                    }.padding(.bottom)

                    VStack {
                        // Inverted binding: "Disable" toggle controls "isEnabled" boolean
                        // When toggle is ON → data transmission is DISABLED (isEnabled = false)
                        // When toggle is OFF → data transmission is ENABLED (isEnabled = true)
                        Toggle("Disable Watchface Data", isOn: Binding(
                            get: { !state.garminSettings.isWatchfaceDataEnabled },
                            set: { state.garminSettings.isWatchfaceDataEnabled = !$0 }
                        ))

                        HStack(alignment: .center) {
                            Text(
                                "Choose if you only want to use a datafield and no supported watchface!"
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    shouldDisplayHint2.toggle()
                                },
                                label: {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.top)
                    }.padding(.bottom)
                }
            ).listRowBackground(Color.chart)

            // MARK: - Datafield Selection Section

            Section(
                header: Text("Datafield Settings"),
                content: {
                    VStack {
                        Picker(
                            selection: $state.garminSettings.datafield,
                            label: Text("Datafield Selection").multilineTextAlignment(.leading)
                        ) {
                            ForEach(GarminDatafield.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }
                        .padding(.top)

                        HStack(alignment: .center) {
                            Text(
                                "Choose which datafield to support. Can be used independently of watchface selection."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    shouldDisplayHint4.toggle()
                                },
                                label: {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.top)
                    }.padding(.bottom)
                }
            ).listRowBackground(Color.chart)

            // MARK: - Data Field Selection Section

            Section(
                header: Text("Watch App Display Settings"),
                content: {
                    VStack {
                        Picker(
                            selection: $state.garminSettings.primaryAttributeChoice,
                            label: Text("Data Choice 1").multilineTextAlignment(.leading)
                        ) {
                            ForEach(GarminPrimaryAttributeChoice.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }.padding(.top)
                        HStack(alignment: .center) {
                            Text(
                                "Choose between displayed data types on Garmin device."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    shouldDisplayHint3.toggle()
                                },
                                label: {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.top)
                    }.padding(.bottom)

                    VStack {
                        Picker(
                            selection: $state.garminSettings.secondaryAttributeChoice,
                            label: Text("Data Choice 2").multilineTextAlignment(.leading)
                        ) {
                            ForEach(GarminSecondaryAttributeChoice.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }.padding(.top)
                        HStack(alignment: .center) {
                            Text(
                                "Choose between displayed data types on Garmin device."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    shouldDisplayHint3.toggle()
                                },
                                label: {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.top)
                    }.padding(.bottom)
                }
            ).listRowBackground(Color.chart)
        }
        .listSectionSpacing(sectionSpacing)
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))

        // MARK: - Help Sheets

        .sheet(isPresented: $shouldDisplayHint1) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint1,
                hintLabel: "Choose Garmin Watchface",
                hintText: Text(
                    "Choose which watchface on your Garmin device you wish to provide data for. You can independently select which datafield to use in the next section.\n\n" +
                        "• Trio – The original Trio watchface, developed by Ivan Valkou.\n" +
                        "• Swissalpine – Originally developed for AAPS, adapted to work with Trio.\n\n" +
                        "You must use this configuration setting here BEFORE you switch the watchface on your Garmin device to another watchface.\n\n" +
                        "⚠️ Changing the watchface will automatically disable data transmission. You will be prompted to resume data transmission after you have changed the watchface on your Garmin device."
                ),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
        .sheet(isPresented: $shouldDisplayHint4) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint4,
                hintLabel: "Choose Garmin Datafield",
                hintText: Text(
                    "Choose which datafield on your Garmin device you wish to provide data for. The datafield can be used independently from the watchface selection.\n\n" +
                        "• Trio – The original Trio datafield, developed by Pierre.\n" +
                        "• Swissalpine – Originally developed for AAPS, adapted to work with Trio.\n\n" +
                        "Select 'None' if you don't want to use a datafield, or want to preserve battery while not exercising."
                ),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
        .sheet(isPresented: $shouldDisplayHint2) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint2,
                hintLabel: "Disable watchface data transmission",
                hintText: Text(
                    "Important: If you want to use a different watchface on your Garmin device that has no data requirement from this app, disable data transmission to the Garmin watchface app! Otherwise you will not be able to get current data once you re-enable the supported watchface that shows Trio data and you will have to re-install it on your Garmin device.\n\n" +
                        "Note: When switching between supported watchfaces, data transmission is automatically disabled. You will be prompted to resume data transmission after you have changed the watchface on your Garmin device."
                ),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
        .sheet(isPresented: $shouldDisplayHint3) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint3,
                hintLabel: "Choose data support",
                hintText: Text(
                    "Choose which data types, along with Blood Glucose and IOB etc., you want to show on your Garmin device. That data type will be shown both on watchface and datafield.\n\n" +
                        "Data Choice 1 options:\n" +
                        "• COB – Carbs On Board\n" +
                        "• ISF – Insulin Sensitivity Factor\n" +
                        "• Sens Ratio – Sensitivity Ratio\n\n" +
                        "Data Choice 2 options:\n" +
                        "• Temp Basal Rate\n" +
                        "• Eventual Glucose"
                ),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
        .confirmationDialog("Watchface Changed", isPresented: $shouldShowWatchfaceSwitchConfirmDialog) {
            Button("Resume Data Transmission") {
                state.resumeDataTransmission()
            }
        } message: {
            Text(
                "Data transmission has been disabled. Now select the new watchface on your Garmin device and resume data transmission once done."
            )
        }
    }
}
