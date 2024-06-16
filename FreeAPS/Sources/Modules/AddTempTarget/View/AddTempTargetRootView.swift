import CoreData
import SwiftUI
import Swinject

extension AddTempTarget {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var isPromptPresented = false
        @State private var isRemoveAlertPresented = false
        @State private var removeAlert: Alert?
        @State private var isEditing = false

        @FetchRequest(
            entity: TempTargetsSlider.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var isEnabledArray: FetchedResults<TempTargetsSlider>

        @Environment(\.colorScheme) var colorScheme

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        private var color: LinearGradient {
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
                if !state.presets.isEmpty {
                    Section(header: Text("Presets")) {
                        ForEach(state.presets) { preset in
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
                            Text("\(state.percentage.formatted(.number)) % Insulin")
                                .foregroundColor(isEditing ? .orange : .blue)
                                .font(.largeTitle)
                                .padding(.vertical)
                            Slider(
                                value: $state.percentage,
                                in: 15 ...
                                    min(Double(state.maxValue * 100), 200),
                                step: 1,
                                onEditingChanged: { editing in
                                    isEditing = editing
                                }
                            )
                            // Only display target slider when not 100 %
                            if state.percentage != 100 {
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
                            TextFieldWithToolBar(text: $state.duration, placeholder: "0", numberFormatter: formatter)
                            Text("minutes").foregroundColor(.secondary)
                        }
                        DatePicker("Date", selection: $state.date)
                        Button { isPromptPresented = true }
                        label: { Text("Save as preset") }
                    }.listRowBackground(Color.chart)
                }
                if state.viewPercantage {
                    Section {
                        HStack {
                            Text("Duration")
                            Spacer()
                            TextFieldWithToolBar(text: $state.duration, placeholder: "0", numberFormatter: formatter)
                            Text("minutes").foregroundColor(.secondary)
                        }
                        DatePicker("Date", selection: $state.date)
                        Button { isPromptPresented = true }
                        label: { Text("Save as preset") }
                            .disabled(state.duration == 0)
                    }.listRowBackground(Color.chart)
                }

                Section {
                    Button { state.enact() }
                    label: { Text("Enact") }
                    Button { state.cancel() }
                    label: { Text("Cancel Temp Target") }
                }.listRowBackground(Color.chart)
            }.scrollContentBackground(.hidden).background(color)
                .popover(isPresented: $isPromptPresented) {
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
                .navigationTitle("Enact Temp Target")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") {
                            state.hideModal()
                        }
                    }
                }
        }

        private func presetView(for preset: TempTarget) -> some View {
            var low = preset.targetBottom
            var high = preset.targetTop
            if state.units == .mmolL {
                low = low?.asMmolL
                high = high?.asMmolL
            }
            return HStack {
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
                }

                Image(systemName: "xmark.circle").foregroundColor(.secondary)
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
        }
    }
}
