import CoreData
import SwiftUI
import Swinject

extension OverrideProfilesConfig {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()

        @State private var isEditing = false
        @State private var showProfileCreationSheet = false
        @State private var showingDetail = false
        @State private var showCheckmark: Bool = false
        @State private var selectedPresetID: String?
        @State private var showOverrideEditSheet = false
        @State private var selectedProfile: OverrideStored?
        // temp targets
        @State private var isPromptPresented = false
        @State private var isRemoveAlertPresented = false
        @State private var removeAlert: Alert?
        @State private var isEditingTT = false

        @Environment(\.managedObjectContext) var moc
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

        @FetchRequest(
            entity: TempTargetsSlider.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var isEnabledArray: FetchedResults<TempTargetsSlider>

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
            }
            formatter.roundingMode = .halfUp
            return formatter
        }

        var body: some View {
            VStack {
                Picker("Tab", selection: $state.selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Text(NSLocalizedString(tab.name, comment: "")).tag(tab)
                    }
                }
                .pickerStyle(.segmented).padding(.horizontal, 10)

                Form {
                    switch state.selectedTab {
                    case .profiles: profiles()
                    case .tempTargets: tempTargets() }
                }.scrollContentBackground(.hidden).background(color)
                    .onAppear(perform: configureView)
                    .navigationBarTitle("Profiles")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            switch state.selectedTab {
                            case .profiles:
                                Button(action: {
                                    showProfileCreationSheet = true
                                }, label: {
                                    HStack {
                                        Text("Add Profile")
                                        Image(systemName: "plus")
                                    }
                                })
                            default:
                                EmptyView()
                            }
                        }
                    }
                    .sheet(isPresented: $showOverrideEditSheet, onDismiss: {
                        Task {
                            await state.resetStateVariables()
                            showOverrideEditSheet = false
                        }

                    }) {
                        if let profile = selectedProfile {
                            EditProfileForm(profile: profile, state: state)
                        }
                    }
                    .sheet(isPresented: $showProfileCreationSheet, onDismiss: {
                        Task {
                            await state.resetStateVariables()
                            showProfileCreationSheet = false
                        }
                    }) {
                        AddProfileForm(state: state)
                    }
            }.background(color)
        }

        @ViewBuilder func profiles() -> some View {
            if state.profilePresets.isNotEmpty {
                overridePresets

                if state.isEnabled, state.activeOverrideName.isNotEmpty {
                    currentActiveOverride
                }
            } else {
                defaultText
            }
            cancelProfileButton
        }

        private var defaultText: some View {
            Text("Add Preset or Override by tapping the '+'")
        }

        private var overridePresets: some View {
            Section {
                ForEach(state.profilePresets) { preset in
                    profilesView(for: preset)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .none) {
                                state.invokeProfilePresetDeletion(preset.objectID)
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .tint(.red)
                            }
                            Button(action: {
                                selectedProfile = preset
                                showOverrideEditSheet = true
                            }, label: {
                                Label("Edit", systemImage: "pencil")
                                    .tint(.blue)
                            })
                        }
                }.listRowBackground(Color.chart)
            } header: {
                Text("Presets")
            } footer: {
                Text("Swipe left to edit or delete a Profile Preset")
            }
        }

        private var currentActiveOverride: some View {
            Section {
                HStack {
                    Text("\(state.activeOverrideName) is running")

                    Spacer()
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(Color.blue)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedProfile = state.currentActiveOverride
                    showOverrideEditSheet = true
                }
            }
            .listRowBackground(Color.blue.opacity(0.2))
        }

        private var cancelProfileButton: some View {
            Button(action: {
                Task {
                    await state.disableAllActiveProfiles()
                }
            }, label: {
                Text("Cancel Profile")

            })
                .frame(maxWidth: .infinity, alignment: .center)
                .disabled(!state.isEnabled)
                .listRowBackground(!state.isEnabled ? Color(.systemGray4) : Color(.systemRed))
                .tint(.white)
        }

        @ViewBuilder func tempTargets() -> some View {
            if !state.presetsTT.isEmpty {
                Section(header: Text("Presets")) {
                    ForEach(state.presetsTT) { preset in
                        presetView(for: preset)
                    }
                }.listRowBackground(Color.chart)
            }

            HStack {
                Text("Experimental")
                Toggle(isOn: $state.viewPercantage) {}.controlSize(.mini)
                Image(systemName: "figure.highintensity.intervaltraining")
                Image(systemName: "fork.knife")
            }.listRowBackground(Color.chart)

            if state.viewPercantage {
                Section {
                    VStack {
                        Text("\(state.percentageTT.formatted(.number)) % Insulin")
                            .foregroundColor(isEditingTT ? .orange : .blue)
                            .font(.largeTitle)
                            .padding(.vertical)
                        Slider(
                            value: $state.percentageTT,
                            in: 15 ...
                                min(Double(state.maxValue * 100), 200),
                            step: 1,
                            onEditingChanged: { editing in
                                isEditingTT = editing
                            }
                        )
                        // Only display target slider when not 100 %
                        if state.percentageTT != 100 {
                            Spacer()
                            Divider()
                            Text(
                                (
                                    state
                                        .units == .mmolL ?
                                        "\(state.computeTarget().asMmolL.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))) mmol/L" :
                                        "\(state.computeTarget().formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))) mg/dl"
                                )
                                    + NSLocalizedString(" Target Glucose", comment: "")
                            )
                            .foregroundColor(.green)
                            .padding(.vertical)

                            Slider(
                                value: $state.hbt,
                                in: 101 ... 295,
                                step: 1
                            ).accentColor(.green)
                        }
                    }
                }.listRowBackground(Color.chart)
            } else {
                Section(header: Text("Custom")) {
                    HStack {
                        Text("Target")
                        Spacer()
                        TextFieldWithToolBar(text: $state.low, placeholder: "0", numberFormatter: formatter)
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Duration")
                        Spacer()
                        TextFieldWithToolBar(text: $state.durationTT, placeholder: "0", numberFormatter: formatter)
                        Text("minutes").foregroundColor(.secondary)
                    }
                    DatePicker("Date", selection: $state.date)
                    HStack {
                        Button { state.enact() }
                        label: { Text("Enact") }
                            .disabled(state.durationTT == 0)
                            .buttonStyle(BorderlessButtonStyle())
                            .font(.callout)
                            .controlSize(.mini)

                        Button { isPromptPresented = true }
                        label: { Text("Save as preset") }
                            .disabled(state.durationTT == 0)
                            .tint(.orange)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .buttonStyle(BorderlessButtonStyle())
                            .controlSize(.mini)
                    }
                }.listRowBackground(Color.chart)
            }
            if state.viewPercantage {
                Section {
                    HStack {
                        Text("Duration")
                        Spacer()
                        TextFieldWithToolBar(text: $state.durationTT, placeholder: "0", numberFormatter: formatter)
                        Text("minutes").foregroundColor(.secondary)
                    }
                    DatePicker("Date", selection: $state.date)
                    HStack {
                        Button { state.enact() }
                        label: { Text("Enact") }
                            .disabled(state.durationTT == 0)
                            .buttonStyle(BorderlessButtonStyle())
                            .font(.callout)
                            .controlSize(.mini)

                        Button { isPromptPresented = true }
                        label: { Text("Save as preset") }
                            .disabled(state.durationTT == 0)
                            .tint(.orange)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .buttonStyle(BorderlessButtonStyle())
                            .controlSize(.mini)
                    }
                }.listRowBackground(Color.chart)
            }

            Section {
                Button { state.cancel() }
                label: {
                    HStack {
                        Spacer()
                        Text("Cancel Temp Target")
                        Spacer()
                        Image(systemName: "xmark.app")
                            .font(.title)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .disabled(state.storage.current() == nil)
                .listRowBackground(state.storage.current() == nil ? Color(.systemGray4) : Color(.systemRed))
                .tint(.white)
            }.popover(isPresented: $isPromptPresented) {
                Form {
                    Section(header: Text("Enter preset name")) {
                        TextField("Name", text: $state.newPresetName)
                        Button {
                            state.save()
                            isPromptPresented = false
                        }
                        label: { Text("Save") }
                        Button { isPromptPresented = false }
                        label: { Text("Cancel") }
                    }
                }
            }
            .onAppear {
                configureView()
                state.hbt = isEnabledArray.first?.hbt ?? 160
            }
        }

        private func presetView(for preset: TempTarget) -> some View {
            var low = preset.targetBottom
            var high = preset.targetTop
            if state.units == .mmolL {
                low = low?.asMmolL
                high = high?.asMmolL
            }
            let isSelected = preset.id == selectedPresetID

            return ZStack(alignment: .trailing, content: {
                HStack {
                    VStack {
                        HStack {
                            Text(preset.displayName)
                            Spacer()
                        }
                        HStack(spacing: 2) {
                            Text(
                                "\(formatter.string(from: (low ?? 0) as NSNumber)!) - \(formatter.string(from: (high ?? 0) as NSNumber)!)"
                            )
                            .foregroundColor(.secondary)
                            .font(.caption)

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
                        }.padding(.top, 2)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        state.enactPreset(id: preset.id)
                        selectedPresetID = preset.id
                        showCheckmark.toggle()

                        // deactivate showCheckmark after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            showCheckmark = false
                        }
                    }

                    Image(systemName: "xmark.circle").foregroundColor(showCheckmark && isSelected ? Color.clear : Color.secondary)
                        .contentShape(Rectangle())
                        .padding(.vertical)
                        .onTapGesture {
                            removeAlert = Alert(
                                title: Text("Are you sure?"),
                                message: Text("Delete preset \"\(preset.displayName)\""),
                                primaryButton: .destructive(Text("Delete"), action: { state.removePreset(id: preset.id) }),
                                secondaryButton: .cancel()
                            )
                            isRemoveAlertPresented = true
                        }
                        .alert(isPresented: $isRemoveAlertPresented) {
                            removeAlert!
                        }
                }
                if showCheckmark && isSelected {
                    // show checkmark to indicate if the preset was actually pressed
                    Image(systemName: "checkmark.circle.fill")
                        .imageScale(.large)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.green)
                }
            })
        }

        @ViewBuilder private func profilesView(for preset: OverrideStored) -> some View {
            let target = state.units == .mmolL ? (((preset.target ?? 0) as NSDecimalNumber) as Decimal)
                .asMmolL : (preset.target ?? 0) as Decimal
            let duration = (preset.duration ?? 0) as Decimal
            let name = ((preset.name ?? "") == "") || (preset.name?.isEmpty ?? true) ? "" : preset.name!
            let percent = preset.percentage / 100
            let perpetual = preset.indefinite
            let durationString = perpetual ? "" : "\(formatter.string(from: duration as NSNumber)!)"
            let scheduledSMBstring = (preset.smbIsOff && preset.smbIsAlwaysOff) ? "Scheduled SMBs" : ""
            let smbString = (preset.smbIsOff && scheduledSMBstring == "") ? "SMBs are off" : ""
            let targetString = target != 0 ? "\(glucoseFormatter.string(from: target as NSNumber)!)" : ""
            let maxMinutesSMB = (preset.smbMinutes as Decimal?) != nil ? (preset.smbMinutes ?? 0) as Decimal : 0
            let maxMinutesUAM = (preset.uamMinutes as Decimal?) != nil ? (preset.uamMinutes ?? 0) as Decimal : 0
            let isfString = preset.isf ? "ISF" : ""
            let crString = preset.cr ? "CR" : ""
            let dash = crString != "" ? "/" : ""
            let isfAndCRstring = isfString + dash + crString
            let isSelected = preset.id == selectedPresetID

            if name != "" {
                ZStack(alignment: .trailing, content: {
                    HStack {
                        VStack {
                            HStack {
                                Text(name)
                                Spacer()
                            }
                            HStack(spacing: 5) {
                                Text(percent.formatted(.percent.grouping(.never).rounded().precision(.fractionLength(0))))
                                if targetString != "" {
                                    Text(targetString)
                                    Text(targetString != "" ? state.units.rawValue : "")
                                }
                                if durationString != "" { Text(durationString + (perpetual ? "" : "min")) }
                                if smbString != "" { Text(smbString).foregroundColor(.secondary).font(.caption) }
                                if scheduledSMBstring != "" { Text(scheduledSMBstring) }
                                if preset.advancedSettings {
                                    Text(maxMinutesSMB == 0 ? "" : maxMinutesSMB.formatted() + " SMB")
                                    Text(maxMinutesUAM == 0 ? "" : maxMinutesUAM.formatted() + " UAM")
                                    Text(isfAndCRstring)
                                }
                                Spacer()
                            }
                            .padding(.top, 2)
                            .foregroundColor(.secondary)
                            .font(.caption)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                let objectID = preset.objectID
                                await state.enactProfilePreset(withID: objectID)
                                state.hideModal()
                                showCheckmark.toggle()
                                selectedPresetID = preset.id

                                // deactivate showCheckmark after 3 seconds
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                    showCheckmark = false
                                }
                            }
                        }
                    }
                    // show checkmark to indicate if the preset was actually pressed
                    if showCheckmark && isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .imageScale(.large)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.green)
                    }
                })
            }
        }
    }
}
