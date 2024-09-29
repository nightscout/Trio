import SwiftUI
import Swinject

extension BasalProfileEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var editMode = EditMode.inactive

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.timeStyle = .short
            return formatter
        }

        private var rateFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        var body: some View {
            Form {
                Section(header: Text("Schedule")) {
                    list
                    addButton
                }
                Section {
                    HStack {
                        Text("Total")
                            .bold()
                            .foregroundColor(.primary)
                        Spacer()
                        Text(rateFormatter.string(from: state.total as NSNumber) ?? "0")
                            .foregroundColor(.primary) +
                            Text(" U/day")
                            .foregroundColor(.secondary)
                    }
                }
                Section {
                    HStack {
                        if state.syncInProgress {
                            ProgressView().padding(.trailing, 10)
                        }
                        Button { state.save() }
                        label: {
                            Text(state.syncInProgress ? "Saving..." : "Save on Pump")
                        }
                        .disabled(state.syncInProgress || state.items.isEmpty)
                    }
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("Basal Profile")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(
                trailing: EditButton()
            )
            .environment(\.editMode, $editMode)
            .onAppear {
                state.validate()
            }
        }

        private func pickers(for index: Int) -> some View {
            GeometryReader { geometry in
                VStack {
                    HStack {
                        Text("Rate").frame(width: geometry.size.width / 2)
                        Text("Time").frame(width: geometry.size.width / 2)
                    }
                    HStack(spacing: 0) {
                        Picker(selection: $state.items[index].rateIndex, label: EmptyView()) {
                            ForEach(0 ..< state.rateValues.count, id: \.self) { i in
                                Text(
                                    (
                                        self.rateFormatter
                                            .string(from: state.rateValues[i] as NSNumber) ?? ""
                                    ) + " U/hr"
                                ).tag(i)
                            }
                        }
                        .frame(maxWidth: geometry.size.width / 2)
                        .clipped()

                        Picker(selection: $state.items[index].timeIndex, label: EmptyView()) {
                            ForEach(state.availableTimeIndices(index), id: \.self) { i in
                                Text(
                                    self.dateFormatter
                                        .string(from: Date(
                                            timeIntervalSince1970: state
                                                .timeValues[i]
                                        ))
                                ).tag(i)
                            }
                        }
                        .frame(maxWidth: geometry.size.width / 2)
                        .clipped()
                    }
                }
            }
        }

        private var list: some View {
            List {
                ForEach(state.items.indexed(), id: \.1.id) { index, item in
                    NavigationLink(destination: pickers(for: index)) {
                        HStack {
                            Text("Rate").foregroundColor(.secondary)
                            Text(
                                "\(rateFormatter.string(from: state.rateValues[item.rateIndex] as NSNumber) ?? "0") U/hr"
                            )
                            Spacer()
                            Text("starts at").foregroundColor(.secondary)
                            Text(
                                "\(dateFormatter.string(from: Date(timeIntervalSince1970: state.timeValues[item.timeIndex])))"
                            )
                        }
                    }
                    .moveDisabled(true)
                }
                .onDelete(perform: onDelete)
            }
        }

        private var addButton: some View {
            guard state.canAdd else {
                return AnyView(EmptyView())
            }

            switch editMode {
            case .inactive:
                return AnyView(Button(action: onAdd) { Text("Add") })
            default:
                return AnyView(EmptyView())
            }
        }

        func onAdd() {
            state.add()
        }

        private func onDelete(offsets: IndexSet) {
            state.items.remove(atOffsets: offsets)
            state.validate()
            state.calcTotal()
        }
    }
}
