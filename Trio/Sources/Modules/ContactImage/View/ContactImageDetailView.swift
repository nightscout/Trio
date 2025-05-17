import SwiftUI

struct ContactImageDetailView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    @ObservedObject var state: ContactImage.StateModel

    @State private var contactImageEntry: ContactImageEntry
    @State private var initialContactImageEntry: ContactImageEntry

    init(entry: ContactImageEntry, state: ContactImage.StateModel) {
        self.state = state
        _contactImageEntry = State(initialValue: entry)
        _initialContactImageEntry = State(initialValue: entry)
    }

    var body: some View {
        VStack {
            HStack {
                Spacer()
                ZStack {
                    Circle()
                        .fill(.black)
                        .foregroundColor(.white)
                        .frame(width: 100, height: 100)
                    Image(uiImage: ContactPicture.getImage(contact: contactImageEntry, state: state.state))
                        .resizable()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                    Circle()
                        .stroke(lineWidth: 2)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 100, height: 100)
                }
                Spacer()
            }
            .padding(.top, 80)
            .padding(.bottom)

            Form {
                Section(
                    header: Text("Contact Name"),
                    content: {
                        TextField("Enter Name (Optional)", text: $contactImageEntry.name)
                    }
                ).listRowBackground(Color.chart)

                Section(header: Text("Style")) {
                    Picker("Layout", selection: $contactImageEntry.layout) {
                        ForEach(ContactImageLayout.allCases, id: \.id) { layout in
                            Text(layout.displayName).tag(layout)
                        }
                    }.onChange(of: contactImageEntry.layout, { oldLayout, newLayout in
                        if oldLayout != newLayout, newLayout == .split {
                            contactImageEntry.top = .glucose
                        } else {
                            contactImageEntry.top = .none
                        }
                    })

                    Toggle("High Contrast Mode", isOn: $contactImageEntry.hasHighContrast)
                }.listRowBackground(Color.chart)

                Section(header: Text("Display Values")) {
                    Picker("Top Value", selection: $contactImageEntry.top) {
                        ForEach(ContactImageValue.allCases, id: \.id) { value in
                            Text(value.displayName).tag(value)
                        }
                    }

                    if contactImageEntry.layout == .default {
                        Picker("Primary", selection: $contactImageEntry.primary) {
                            ForEach(ContactImageValue.allCases, id: \.id) { value in
                                Text(value.displayName).tag(value)
                            }
                        }
                    }

                    Picker("Bottom Value", selection: $contactImageEntry.bottom) {
                        ForEach(ContactImageValue.allCases, id: \.id) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                }.listRowBackground(Color.chart)

                // Ring Settings Section
                Section(header: Text("Ring Settings")) {
                    Picker("Ring Type", selection: $contactImageEntry.ring) {
                        ForEach(ContactImageLargeRing.allCases, id: \.self) { ring in
                            Text(ring.displayName).tag(ring)
                        }
                    }

                    if contactImageEntry.ring != .none {
                        Picker("Ring Width", selection: $contactImageEntry.ringWidth) {
                            ForEach(ContactImageEntry.RingWidth.allCases, id: \.self) { width in
                                Text(width.displayName).tag(width)
                            }
                        }
                        Picker("Ring Gap", selection: $contactImageEntry.ringGap) {
                            ForEach(ContactImageEntry.RingGap.allCases, id: \.self) { gap in
                                Text(gap.displayName).tag(gap)
                            }
                        }
                    }
                }.listRowBackground(Color.chart)

                // Font Settings Section
                Section(header: Text("Font Settings")) {
                    fontSizePicker
                    if contactImageEntry.layout == .split {
                        secondaryFontSizePicker
                    }
                    fontWeightPicker
                    fontWidthPicker
                }.listRowBackground(Color.chart)
            }
        }
        .navigationTitle("Edit Contact Items")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) { stickySaveButton }
        .listSectionSpacing(10)
        .padding(.top, 30)
        .ignoresSafeArea(edges: .top)
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(
                    action: {
                        state.isHelpSheetPresented.toggle()
                    },
                    label: {
                        Image(systemName: "questionmark.circle")
                    }
                )
            }
        }
        .sheet(isPresented: $state.isHelpSheetPresented) {
            ContactImageHelpView(state: state, helpSheetDetent: $state.helpSheetDetent)
        }
    }

    private func saveChanges() {
        Task {
            await state.updateContact(with: contactImageEntry)
            dismiss()
        }
    }

    var stickySaveButton: some View {
        var isUnchanged: Bool { initialContactImageEntry == contactImageEntry }

        return ZStack {
            Rectangle()
                .frame(width: UIScreen.main.bounds.width, height: 65)
                .foregroundStyle(colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white)
                .background(.thinMaterial)
                .opacity(0.8)
                .clipShape(Rectangle())

            Button(action: {
                saveChanges()
            }, label: {
                Text("Save").padding(10)
            })
                .frame(width: UIScreen.main.bounds.width * 0.9, alignment: .center)
                .background(isUnchanged ? Color(.systemGray4) : Color(.systemBlue))
                .disabled(isUnchanged)
                .tint(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(5)
        }
    }

    private var fontSizePicker: some View {
        Picker("Font Size", selection: $contactImageEntry.fontSize) {
            ForEach(ContactImageEntry.FontSize.allCases, id: \.self) { size in
                Text(size.displayName).tag(size)
            }
        }
    }

    private var secondaryFontSizePicker: some View {
        Picker("Secondary Font Size", selection: $contactImageEntry.secondaryFontSize) {
            ForEach(ContactImageEntry.FontSize.allCases, id: \.self) { size in
                Text(size.displayName).tag(size)
            }
        }
    }

    private var fontWeightPicker: some View {
        Picker("Font Weight", selection: $contactImageEntry.fontWeight) {
            ForEach(
                [Font.Weight.light, Font.Weight.regular, Font.Weight.medium, Font.Weight.bold, Font.Weight.black],
                id: \.self
            ) { weight in
                Text("\(weight.displayName)".capitalized).tag(weight)
            }
        }
    }

    private var fontWidthPicker: some View {
        Picker("Font Width", selection: $contactImageEntry.fontWidth) {
            ForEach(
                [Font.Width.standard, Font.Width.expanded],
                id: \.self
            ) { width in
                Text("\(width.displayName)".capitalized).tag(width)
            }
        }
    }
}
