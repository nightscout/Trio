import CoreData
import SwiftUI
import Swinject

extension AddTempTarget {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var isPromtPresented = false
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
                                    Button(role: .destructive) {
                                        state.removePreset(id: preset.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
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
                        }
                    }
                }
                
                HStack {
                    Text("Experimental")
                    Toggle(isOn: $state.viewPercantage) {}.controlSize(.mini)
                    Image(systemName: "figure.highintensity.intervaltraining")
                    Image(systemName: "fork.knife")
                }
                
                if state.viewPercantage {
                    Section(
                        header: Text("")
                    ) {
                        VStack {
                            Slider(
                                value: $state.percentage,
                                in: 15 ...
                                min(Double(state.maxValue * 100), 200),
                                step: 1,
                                onEditingChanged: { editing in
                                    isEditing = editing
                                }
                            )
                            HStack {
                                Text("\(state.percentage.formatted(.number)) % Insulin")
                                    .foregroundColor(isEditing ? .orange : .blue)
                                    .font(.largeTitle)
                            }
                            // Only display target slider when not 100 %
                            if state.percentage != 100 {
                                Divider()
                                
                                Slider(
                                    value: $state.hbt,
                                    in: 101 ... 295,
                                    step: 1
                                ).accentColor(.green)
                                
                                HStack {
                                    Text(
                                        (
                                            state
                                                .units == .mmolL ?
                                            "\(state.computeTarget().asMmolL.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))) mmol/L" :
                                                "\(state.computeTarget().formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))) mg/dl"
                                        )
                                        + NSLocalizedString("  Target Glucose", comment: "")
                                    )
                                    .foregroundColor(.green)
                                }
                            }
                        }
                    }
                } else {
                    Section(header: Text("Custom")) {
                        HStack {
                            Text("Target")
                            Spacer()
                            DecimalTextField("0", value: $state.low, formatter: formatter, cleanInput: true)
                            Text(state.units.rawValue).foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Duration")
                            Spacer()
                            DecimalTextField("0", value: $state.duration, formatter: formatter, cleanInput: true)
                            Text("minutes").foregroundColor(.secondary)
                        }
                        DatePicker("Date", selection: $state.date)
                        Button { isPromtPresented = true }
                    label: { Text("Save as preset") }
                    }
                }
                if state.viewPercantage {
                    Section {
                        HStack {
                            Text("Duration")
                            Spacer()
                            DecimalTextField("0", value: $state.duration, formatter: formatter, cleanInput: true)
                            Text("minutes").foregroundColor(.secondary)
                        }
                        DatePicker("Date", selection: $state.date)
                        Button { isPromtPresented = true }
                    label: { Text("Save as preset") }
                            .disabled(state.duration == 0)
                    }
                }
                
                Section {
                    Button { state.enact() }
                label: { Text("Enact") }
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
        
        @ViewBuilder private func editPresetPopover() -> some View {
            Form {
                Section(header: Text("Edit Preset")) {
                    TextField("Name", text: $state.newPresetName)
                    Text(displayString)
                        .foregroundColor(.secondary)
                        .font(.caption)
                    HStack {
                        Text("New Target")
                        Spacer()
                        DecimalTextField("0", value: $state.low, formatter: formatter, cleanInput: true)
                        Text(state.units.rawValue)
                    }
                    HStack {
                        Text("New Duration")
                        Spacer()
                        DecimalTextField("0", value: $state.duration, formatter: formatter, cleanInput: true)
                        Text("minutes")
                    }
                }
                Section {
                    Button("Save") {
                        guard let selectedPreset = selectedPreset else { return }
                        state.updatePreset(
                            selectedPreset,
                            low: state.units == .mmolL ? state.low.asMgdL : state.low
                        )
                        isEditSheetPresented = false
                    }
                    .disabled(state.newPresetName.isEmpty)
                    
                    Button("Cancel") {
                        isEditSheetPresented = false
                    }
                }
            }
        }
        
        private func presetView(for preset: TempTarget) -> some View {
            var low = preset.targetBottom
            var high = preset.targetBottom // change to only use targetBottom instead of targetTop
            if state.units == .mmolL {
                low = low?.asMmolL
                high = high?.asMmolL
            }
            return HStack {
                VStack {
                    HStack {
                        Text(preset.displayName)
                        Spacer()
                        Button {
                            selectedPreset = preset
                            state.newPresetName = preset.displayName
                            state.low = state.units == .mmolL ? preset.targetBottom?
                                .asMmolL ?? 0 : preset.targetBottom ?? 0
                            state.duration = preset.duration
                            state.date = preset.date as? Date ?? Date()
                            isEditSheetPresented = true
                        } label: {}
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
    }
}

extension AddTempTarget.StateModel {
    func updatePreset(_ preset: TempTarget, low: Decimal) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = TempTarget(
                id: preset.id,
                name: newPresetName,
                createdAt: preset.createdAt,
                targetTop: low,
                targetBottom: low,
                duration: duration,
                enteredBy: preset.enteredBy,
                reason: newPresetName
            )
            storage.storePresets(presets)
        }
    }
}
