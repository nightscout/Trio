import Contacts
import ContactsUI
import SwiftUI
import Swinject

extension ContactTrick {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State private var isAddSheetPresented = false

        var body: some View {
            NavigationView {
                List {
                    ForEach(state.contactTrickEntries, id: \.id) { entry in
                        NavigationLink(destination: ContactTrickDetailView(entry: entry, state: state)) {
                            Text("\(entry.name)")
                        }
                    }
                    .onDelete(perform: onDelete)
                }
                .navigationTitle("Contact Tricks")
                .onAppear(perform: configureView)
                .navigationBarItems(
                    trailing: Button(action: {
                        isAddSheetPresented.toggle()
                    }) {
                        Image(systemName: "plus")
                    }
                )
                .sheet(isPresented: $isAddSheetPresented) {
                    AddContactTrickSheet(state: state)
                }
            }
        }

        private func onDelete(offsets: IndexSet) {
            Task {
                for offset in offsets {
                    let entry = state.contactTrickEntries[offset]
                    await state.deleteContact(entry: entry)
                }
            }
        }
    }
}

struct AddContactTrickSheet: View {
    @Environment(\.dismiss) var dismiss
    var state: ContactTrick.StateModel

    @State private var name: String = ""
    @State private var isDarkMode: Bool = false
    @State private var ringWidth: ContactTrickEntry.RingWidth = .regular
    @State private var ringGap: ContactTrickEntry.RingGap = .small
    @State private var layout: ContactTrickLayout = .single
    @State private var primary: ContactTrickValue = .glucose
    @State private var top: ContactTrickValue = .none
    @State private var bottom: ContactTrickValue = .none

    var body: some View {
        NavigationView {
            Form {
                TextField("Name", text: $name)
                Section(header: Text("Layout")) {
                    Toggle("Dark Mode", isOn: $isDarkMode)
                    Picker("Layout", selection: $layout) {
                        ForEach(ContactTrickLayout.allCases, id: \.id) { layout in
                            Text(layout.displayName).tag(layout)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                Section(header: Text("Primary Value")) {
                    Picker("Primary", selection: $primary) {
                        ForEach(ContactTrickValue.allCases, id: \.id) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                }

                Section(header: Text("Additional Values")) {
                    Picker("Top Value", selection: $top) {
                        ForEach(ContactTrickValue.allCases, id: \.id) { value in
                            Text(value.displayName).tag(value)
                        }
                    }

                    Picker("Bottom Value", selection: $bottom) {
                        ForEach(ContactTrickValue.allCases, id: \.id) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                }

                Section(header: Text("Ring Settings")) {
                    Picker("Ring Width", selection: $ringWidth) {
                        ForEach(ContactTrickEntry.RingWidth.allCases, id: \.self) { width in
                            Text(width.displayName).tag(width)
                        }
                    }

                    Picker("Ring Gap", selection: $ringGap) {
                        ForEach(ContactTrickEntry.RingGap.allCases, id: \.self) { gap in
                            Text(gap.displayName).tag(gap)
                        }
                    }
                }
            }
            .navigationBarTitle("Add Contact Trick", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: Button("Save") {
                    saveNewEntry()
                }
            )
        }
    }

    private func saveNewEntry() {
        let newEntry = ContactTrickEntry(
            id: UUID(),
            name: name,
            layout: layout,
            ring: .none,
            primary: primary,
            top: top,
            bottom: bottom,
            contactId: nil, // Wird später durch die API gesetzt
            darkMode: isDarkMode,
            ringWidth: ringWidth,
            ringGap: ringGap,
            fontSize: .regular,
            secondaryFontSize: .small,
            fontWeight: .medium,
            fontWidth: .standard
        )
        Task {
            await state.createAndSaveContactTrick(entry: newEntry, name: name)
            dismiss()
        }
    }
}

struct ContactTrickDetailView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var state: ContactTrick.StateModel

    @State private var contactTrickEntry: ContactTrickEntry

    init(entry: ContactTrickEntry, state: ContactTrick.StateModel) {
        self.state = state
        _contactTrickEntry = State(initialValue: entry)
    }

    var body: some View {
        Form {
            TextField("Name", text: $contactTrickEntry.name)
            Section(header: Text("Layout")) {
                Toggle("Dark Mode", isOn: $contactTrickEntry.darkMode)
                Picker("Layout", selection: $contactTrickEntry.layout) {
                    ForEach(ContactTrickLayout.allCases, id: \.id) { layout in
                        Text(layout.displayName).tag(layout)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            Section(header: Text("Primary Value")) {
                Picker("Primary", selection: $contactTrickEntry.primary) {
                    ForEach(ContactTrickValue.allCases, id: \.id) { value in
                        Text(value.displayName).tag(value)
                    }
                }
            }

            Section(header: Text("Additional Values")) {
                Picker("Top Value", selection: $contactTrickEntry.top) {
                    ForEach(ContactTrickValue.allCases, id: \.id) { value in
                        Text(value.displayName).tag(value)
                    }
                }

                Picker("Bottom Value", selection: $contactTrickEntry.bottom) {
                    ForEach(ContactTrickValue.allCases, id: \.id) { value in
                        Text(value.displayName).tag(value)
                    }
                }
            }

            Section(header: Text("Ring Settings")) {
                Picker("Ring Width", selection: $contactTrickEntry.ringWidth) {
                    ForEach(ContactTrickEntry.RingWidth.allCases, id: \.self) { width in
                        Text(width.displayName)
                            .tag(width)
                    }
                }

                Picker("Ring Gap", selection: $contactTrickEntry.ringGap) {
                    ForEach(ContactTrickEntry.RingGap.allCases, id: \.self) { gap in
                        Text(gap.displayName)
                            .tag(gap)
                    }
                }
            }
        }
        .navigationBarTitle("Edit Contact Trick", displayMode: .inline)
        .navigationBarItems(
            trailing: Button("Save") {
                saveChanges()
            }
        )
    }

    private func saveChanges() {
        Task {
            await state.updateContact(entry: contactTrickEntry, newName: contactTrickEntry.name)
            dismiss()
        }
    }
}
