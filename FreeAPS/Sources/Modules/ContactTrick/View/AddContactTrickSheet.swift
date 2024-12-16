import SwiftUI

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
    @State private var ring: ContactTrickLargeRing = .none
    @State private var fontSize: ContactTrickEntry.FontSize = .regular
    @State private var secondaryFontSize: ContactTrickEntry.FontSize = .small
    @State private var fontWeight: Font.Weight = .medium
    @State private var fontWidth: Font.Width = .standard

    private var previewEntry: ContactTrickEntry {
        ContactTrickEntry(
            id: UUID(),
            name: name,
            layout: layout,
            ring: ring,
            primary: primary,
            top: top,
            bottom: bottom,
            contactId: nil, // not needed for preview, gets set later in ContactTrickStateModel via ContactTrickManager
            darkMode: isDarkMode,
            ringWidth: ringWidth,
            ringGap: ringGap,
            fontSize: fontSize,
            secondaryFontSize: secondaryFontSize,
            fontWeight: fontWeight,
            fontWidth: fontWidth
        )
    }

    var body: some View {
        NavigationView {
            Form {
                // TODO: - make this beautiful @Dan

                // Preview Section
                Section {
                    HStack {
                        Spacer()
                        Image(uiImage: ContactPicture.getImage(contact: previewEntry, state: state.previewState))
                            .resizable()
                            .aspectRatio(1, contentMode: .fit)
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                        Spacer()
                    }
                }

                // Name Section
                TextField("Name", text: $name)

                // Layout Section
                Section(header: Text("Layout")) {
                    Toggle("Dark Mode", isOn: $isDarkMode)
                    Picker("Layout", selection: $layout) {
                        ForEach(ContactTrickLayout.allCases, id: \.id) { layout in
                            Text(layout.displayName).tag(layout)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                // Primary Value Section
                Section(header: Text("Primary Value")) {
                    Picker("Primary", selection: $primary) {
                        ForEach(ContactTrickValue.allCases, id: \.id) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                }

                // Additional Values Section
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

                // Ring Settings Section
                Section(header: Text("Ring Settings")) {
                    Picker("Ring Type", selection: $ring) {
                        ForEach(ContactTrickLargeRing.allCases, id: \.self) { ring in
                            Text(ring.displayName).tag(ring)
                        }
                    }
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

                // Font Settings Section
                Section(header: Text("Font Settings")) {
                    fontSizePicker
                    secondaryFontSizePicker
                    fontWeightPicker
                    fontWidthPicker
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

    private var fontSizePicker: some View {
        Picker("Font Size", selection: $fontSize) {
            ForEach(ContactTrickEntry.FontSize.allCases, id: \.self) { size in
                Text(size.displayName).tag(size)
            }
        }
    }

    private var secondaryFontSizePicker: some View {
        Picker("Secondary Font Size", selection: $secondaryFontSize) {
            ForEach(ContactTrickEntry.FontSize.allCases, id: \.self) { size in
                Text(size.displayName).tag(size)
            }
        }
    }

    private var fontWeightPicker: some View {
        Picker("Font Weight", selection: $fontWeight) {
            ForEach(
                [Font.Weight.light, Font.Weight.regular, Font.Weight.medium, Font.Weight.bold, Font.Weight.black],
                id: \.self
            ) { weight in
                Text("\(weight)".capitalized).tag(weight)
            }
        }
    }

    private var fontWidthPicker: some View {
        Picker("Font Width", selection: $fontWidth) {
            ForEach(
                [Font.Width.standard, Font.Width.condensed, Font.Width.expanded],
                id: \.self
            ) { width in
                Text("\(width)".capitalized).tag(width)
            }
        }
    }

    private func saveNewEntry() {
        // Save the currently previewed entry
        Task {
            await state.createAndSaveContactTrick(entry: previewEntry, name: name)
            dismiss()
        }
    }
}
