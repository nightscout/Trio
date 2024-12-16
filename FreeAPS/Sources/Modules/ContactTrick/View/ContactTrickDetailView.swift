import SwiftUI

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
            Section {
                HStack {
                    // TODO: - make this beautiful @Dan
                    Spacer()
                    Image(uiImage: ContactPicture.getImage(contact: contactTrickEntry, state: state.previewState))
                        .resizable()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                    Spacer()
                }
            }

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
            await state.updateContact(with: contactTrickEntry)
            dismiss()
        }
    }
}
