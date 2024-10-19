import CoreData
import SwiftUI
import Swinject

extension AddTempTarget {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var isPromtPresented = false
        @State private var isRemoveAlertPresented = false
        @State private var removeAlert: Alert?
        @State private var isEditing = false
        @State private var selectedPreset: TempTarget?
        @State private var isEditSheetPresented = false

        @FetchRequest(
            entity: TempTargetsSlider.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var isEnabledArray: FetchedResults<TempTargetsSlider>

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        private var displayString: String {
            guard let preset = selectedPreset else { return "" }
            var low = preset.targetBottom
            var high = preset.targetBottom // change to only use targetBottom instead of targetTop
            if state.units == .mmolL {
                low = low?.asMmolL
                high = high?.asMmolL
            }

            let formattedLow = low.flatMap { formatter.string(from: $0 as NSNumber) } ?? ""
            let formattedDuration = formatter.string(from: preset.duration as NSNumber) ?? ""

            return "\(formattedLow) \(state.units.rawValue) for \(formattedDuration) min"
        }

        var body: some View {
            Form {
                if !state.presets.isEmpty {
                    Section(header: Text("Presets")) {
                        ForEach(state.presets) { preset in
                            presetView(for: preset)
                                .swipeActions {
                                    Button(role: .none, action: {
                                        removeAlert = Alert(
                                            title: Text("Are you sure?"),
                                            message: Text("Delete preset \n\(preset.displayName)?"),
                                            primaryButton: .destructive(Text("Delete"), action: {
                                                state.removePreset(id: preset.id)
                                                isRemoveAlertPresented = false
                                            }),
                                            secondaryButton: .cancel()
                                        )
                                        isRemoveAlertPresented = true
                                    }) {
                                        Label("Delete", systemImage: "trash")
                                    }.tint(.red)
                                    Button {
                                        selectedPreset = preset
                                        state.newPresetName = preset.displayName
                                        state.low = state.units == .mmolL ? preset.targetBottom?.asMmolL ?? 0 : preset
                                            .targetBottom ?? 0
                                        state.duration = preset.duration
                                        state.date = preset.date as? Date ?? Date()
                                        isEditSheetPresented = true
                                    } label: {
                                        Label("Edit", systemImage: "square.and.pencil")
                                    }
                                    .tint(.blue)
                                }
                                .alert(isPresented: $isRemoveAlertPresented) {
                                    removeAlert!
                                }
                        }
                    }
                }

                settingsSection(header: "Custom")

                DatePicker("Date", selection: $state.date)
                Button { isPromtPresented = true }
                label: { Text("Save as preset") }
                    .disabled(state.duration == 0)

                Section {
                    Button { state.enact() }
                    label: { Text("Enact") }
                        .disabled(state.duration == 0)
                    Button { state.cancel() }
                    label: { Text("Cancel Temp Target") }
                }
            }
            .popover(isPresented: $isPromtPresented) {
                Form {
                    Section(header: Text("Enter preset name")) {
                        TextField("Name", text: $state.newPresetName)
                    }
                    Section {
                        Button {
                            state.save()
                            isPromtPresented = false
                        }
                        label: { Text("Save") }
                        Button { isPromtPresented = false }
                        label: { Text("Cancel") }
                    }
                }
            }
            .sheet(isPresented: $isEditSheetPresented) {
                editPresetPopover()
                    .padding()
            }
            .onAppear {
                configureView()
                state.hbt = isEnabledArray.first?.hbt ?? 160
            }
            .navigationTitle("Enact Temp Target")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: Button("Close", action: state.hideModal))
        }

        @ViewBuilder func settingsSection(header: String) -> some View {
            HStack {
                Text("Advanced TT")
                Toggle(isOn: $state.viewPercantage) {}
                    .controlSize(.mini)
                    .onChange(of: state.viewPercantage) { newValue in
                        if newValue {
                            guard let selectedPreset = selectedPreset,
                                  let targetBottom = selectedPreset.targetBottom else { return }
                            let computedPercentage = state.computePercentage(target: targetBottom)
                            state.hbt = isEnabledArray.first?
                                .hbt ??
                                160 // how to get hbt from previously saved preset? this takes the last enacted temptarget hbt?
                            state
                                .percentage =
                                Double(truncating: computedPercentage as NSNumber) // now I guess state.percentage needs to become whatever I do on slider
                        }
                    }
                Image(systemName: "figure.highintensity.intervaltraining")
                Image(systemName: "fork.knife")
            }

            if state.viewPercantage {
                Section(
                    header: Text("TT Effect on Insulin")
                ) {
                    VStack {
                        HStack {
                            Text(NSLocalizedString("Target", comment: ""))
                            Spacer()
                            DecimalTextField(
                                "0",
                                value: $state.low,
                                formatter: formatter,
                                cleanInput: true
                            )
                            Text(state.units.rawValue).foregroundColor(.secondary)
                        }

                        if computeSliderLow() != computeSliderHigh() {
                            Text("\(state.percentage.formatted(.number)) % Insulin")
                                .foregroundColor(isEditing ? .orange : .blue)
                                .font(.largeTitle)
                            Slider(
                                value: $state.percentage,
                                in: computeSliderLow() ... computeSliderHigh(),
                                step: 5
                            ) {}
                            minimumValueLabel: { Text("\(computeSliderLow(), specifier: "%.0f")%") }
                            maximumValueLabel: { Text("\(computeSliderHigh(), specifier: "%.0f")%") }
                            onEditingChanged: { editing in
                                isEditing = editing }
                            Divider()
                            Text(
                                state
                                    .units == .mgdL ?
                                    "Half Basal Exercise Target at: \(state.computeHBT().formatted(.number)) mg/dl" :
                                    "Half Basal Exercise Target at: \(state.computeHBT().asMmolL.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))) mmol/L"
                            )
                            .foregroundColor(.secondary)
                            .font(.caption).italic()
                        } else {
                            Text(
                                "You have not enabled the proper Preferences to change sensitivity with chosen TempTarget. Verify Autosens Max > 1 & lowTT lowers Sens is on for lowTT's. For high TTs check highTT raises Sens is on (or Exercise Mode)!"
                            )
                            // .foregroundColor(.loopRed)
                            .font(.caption).italic()
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        }
                    }
                }
            } else {
                Section(header: Text(header)) {
                    HStack {
                        Text("Target")
                        Spacer()
                        TextFieldWithToolBar(text: $state.low, placeholder: "0", numberFormatter: formatter)
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Duration")
                        Spacer()
                        TextFieldWithToolBar(text: $state.duration, placeholder: "0", numberFormatter: formatter)
                        Text("minutes").foregroundColor(.secondary)
                    }
                }
            }
            if state.viewPercantage {
                Section {
                    HStack {
                        Text("Duration")
                        Spacer()
                        TextFieldWithToolBar(text: $state.duration, placeholder: "0", numberFormatter: formatter)
                        Text("minutes").foregroundColor(.secondary)
                    }
                }
            }
        }

        @ViewBuilder private func editPresetPopover() -> some View {
            Form {
                Section(header: Text("Edit Name?")) {
                    TextField("Name", text: $state.newPresetName)
                    Text("Settings before change: \(displayString)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                settingsSection(header: "New target and duration")

                Section {
                    Button("Save") {
                        guard let selectedPreset = selectedPreset else { return }
                        state.updatePreset(selectedPreset)
                        isEditSheetPresented = false
                    }
                    .disabled(state.newPresetName.isEmpty)

                    Button("Cancel") {
                        // Reset the fields and close the sheet
                        resetFields()
                        isEditSheetPresented = false
                    }
                }
            }
            .onAppear {
                guard let selectedPreset = selectedPreset, let targetBottom = selectedPreset.targetBottom else { return }
                let computedPercentage = state.computePercentage(target: targetBottom)
                state
                    .percentage =
                    Double(truncating: computedPercentage as NSNumber) // I guess this needs to come directly from the slider
            }
            .onDisappear {
                if isEditSheetPresented == false {
                    resetFields()
                }
            }
        }

        private func resetFields() {
            state.newPresetName = ""
            state.low = 0
            state.duration = 0
            state.percentage = 100 // Reset experimental slider if necessary
        }

        private func presetView(for preset: TempTarget) -> some View {
            var low = preset.targetBottom
            if state.units == .mmolL {
                low = low?.asMmolL
            }

            return HStack {
                VStack {
                    HStack {
                        Text(preset.displayName)
                        Spacer()
                    }
                    HStack(spacing: 2) {
                        if let lowValue = low,
                           let formattedLow = formatter.string(from: lowValue as NSNumber)
                        {
                            Text(formattedLow)
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }

                        Text(state.units.rawValue)
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("for")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("\(formatter.string(from: preset.duration as NSNumber)!)")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("min")
                            .foregroundColor(.secondary)
                            .font(.caption)

                        Spacer()
                    }.padding(.bottom, 2)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    state.enactPreset(id: preset.id)
                }
            }
        }

        func computeSliderLow() -> Double {
            var minSens: Double = 15
            var target = state.low
            if state.units == .mmolL {
                target = Decimal(round(Double(state.low.asMgdL))) }
            if target == 0 { return minSens }
            if target < 100 ||
                (
                    !state.settingsManager.preferences.highTemptargetRaisesSensitivity && !state.settingsManager.preferences
                        .exerciseMode
                ) { minSens = 100 }
            return minSens
        }

        func computeSliderHigh() -> Double {
            var maxSens = Double(state.maxValue * 100)
            var target = state.low
            if target == 0 { return maxSens }
            if state.units == .mmolL {
                target = Decimal(round(Double(state.low.asMgdL))) }
            if target > 100 || !state.settingsManager.preferences.lowTemptargetLowersSensitivity { maxSens = 100 }
            return maxSens
        }
    }
}
