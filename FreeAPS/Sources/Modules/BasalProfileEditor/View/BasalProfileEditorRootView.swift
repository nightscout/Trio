import SwiftUI
import Swinject

extension BasalProfileEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var editMode = EditMode.inactive

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
                let shouldDisableButton = state.syncInProgress || state.items.isEmpty || !state.hasChanges

                Section(header: Text("Schedule")) {
                    list
                }.listRowBackground(Color.chart)

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
                }.listRowBackground(Color.chart)

                Section {
                    HStack {
                        if state.syncInProgress {
                            ProgressView().padding(.trailing, 10)
                        }
                        Button {
                            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                            impactHeavy.impactOccurred()
                            state.save()
                        } label: {
                            Text(state.syncInProgress ? "Saving..." : "Save")
                        }
                        .disabled(shouldDisableButton)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .tint(.white)
                    }
                }.listRowBackground(shouldDisableButton ? Color(.systemGray4) : Color(.systemBlue))
            }
            .alert(isPresented: $state.showAlert) {
                Alert(
                    title: Text("Unable to Save"),
                    message: Text("Trio could not communicate with your pump. Changes to your basal profile were not saved."),
                    dismissButton: .default(Text("Close"))
                )
            }
            .onChange(of: state.items) { _ in
                state.calcTotal()
            }
            .scrollContentBackground(.hidden).background(color)
            .onAppear(perform: configureView)
            .navigationTitle("Basal Profile")
            .navigationBarTitleDisplayMode(.automatic)
            .toolbar(content: {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    addButton
                }
            })
            .environment(\.editMode, $editMode)
            .onAppear {
                state.validate()
            }
        }

        private func pickers(for index: Int) -> some View {
            Form {
                Section {
                    Picker(selection: $state.items[index].rateIndex, label: Text("Rate")) {
                        ForEach(0 ..< state.rateValues.count, id: \.self) { i in
                            Text(
                                (
                                    self.rateFormatter
                                        .string(from: state.rateValues[i] as NSNumber) ?? ""
                                ) + " U/hr"
                            ).tag(i)
                        }
                    }
                    .onChange(of: state.items[index].rateIndex, perform: { _ in state.calcTotal() })
                }.listRowBackground(Color.chart)

                Section {
                    Picker(selection: $state.items[index].timeIndex, label: Text("Time")) {
                        ForEach(0 ..< state.timeValues.count, id: \.self) { i in
                            Text(
                                self.dateFormatter
                                    .string(from: Date(
                                        timeIntervalSince1970: state
                                            .timeValues[i]
                                    ))
                            ).tag(i)
                        }
                    }
                    .onChange(of: state.items[index].timeIndex, perform: { _ in state.calcTotal() })
                }.listRowBackground(Color.chart)
            }
            .padding(.top)
            .scrollContentBackground(.hidden).background(color)
            .navigationTitle("Set Rate")
            .navigationBarTitleDisplayMode(.automatic)
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
                return AnyView(Button(action: onAdd) { Image(systemName: "plus") })
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
