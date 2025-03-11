import SwiftUI
import Swinject

extension Calibrations {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var manualGlucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.units == .mgdL {
                formatter.maximumIntegerDigits = 3
                formatter.maximumFractionDigits = 0
            } else {
                formatter.maximumIntegerDigits = 2
                formatter.minimumFractionDigits = 0
                formatter.maximumFractionDigits = 1
            }
            formatter.roundingMode = .halfUp
            return formatter
        }

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .short
            return formatter
        }

        var body: some View {
            GeometryReader { geo in
                Form {
                    Section(header: Text("Add calibration")) {
                        HStack {
                            Text("Meter glucose")
                            Spacer()
                            TextFieldWithToolBar(
                                text: $state.newCalibration,
                                placeholder: "0",
                                numberFormatter: manualGlucoseFormatter
                            )
                            Text(state.units.rawValue).foregroundColor(.secondary)
                        }
                        Button {
                            Task {
                                await state.addCalibration()
                            }
                        }
                        label: { Text("Add") }
                            .disabled(state.newCalibration <= 0)
                    }.listRowBackground(Color.chart)

                    Section(header: Text("Info")) {
                        HStack {
                            Text("Slope")
                            Spacer()
                            Text(formatter.string(from: state.slope as NSNumber)!)
                        }
                        HStack {
                            Text("Intercept")
                            Spacer()
                            Text(formatter.string(from: state.intercept as NSNumber)!)
                        }
                    }.listRowBackground(Color.chart)

                    Section(header: Text("Remove")) {
                        Button {
                            state.removeLast()
                        }
                        label: { Text("Remove Last") }
                            .disabled(state.calibrations.isEmpty)

                        Button {
                            state.removeAll()
                        }
                        label: { Text("Remove All") }
                            .disabled(state.calibrations.isEmpty)
                        List {
                            ForEach(state.items) { item in
                                HStack {
                                    Text(dateFormatter.string(from: item.calibration.date))
                                    Spacer()
                                    VStack(alignment: .leading) {
                                        Text("raw: \(item.calibration.x)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("value: \(item.calibration.y)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }

                            }.onDelete(perform: delete)
                        }
                    }.listRowBackground(Color.chart)

                    if state.calibrations.isNotEmpty {
                        Section(header: Text("Chart")) {
                            CalibrationsChart(state: state)
                                .frame(minHeight: geo.size.width)
                        }.listRowBackground(Color.chart)
                    }
                }
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear(perform: configureView)
            .navigationTitle("Calibrations")
            .navigationBarItems(trailing: EditButton().disabled(state.calibrations.isEmpty))
            .navigationBarTitleDisplayMode(.automatic)
        }

        private func delete(at offsets: IndexSet) {
            state.removeAtIndex(offsets[offsets.startIndex])
        }
    }
}
