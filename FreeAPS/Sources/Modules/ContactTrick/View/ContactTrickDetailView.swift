import SwiftUI

struct ContactTrickDetailView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    @ObservedObject var state: ContactTrick.StateModel

    @State private var contactTrickEntry: ContactTrickEntry

    init(entry: ContactTrickEntry, state: ContactTrick.StateModel) {
        self.state = state
        _contactTrickEntry = State(initialValue: entry)
    }

    var body: some View {
        VStack {
            HStack {
                // TODO: - make this beautiful @Dan
                Spacer()
                ZStack {
                    Circle()
                        .fill(contactTrickEntry.darkMode ? .black : .white)
                        .foregroundColor(.white)
                        .frame(width: 100, height: 100)
                    Image(uiImage: ContactPicture.getImage(contact: contactTrickEntry, state: state.previewState))
                        .resizable()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                    Circle()
                        .stroke(lineWidth: 2)
                        .foregroundColor(.white)
                        .frame(width: 100, height: 100)
                }
                Spacer()
            }
            .padding(.top, 80)
            .padding(.bottom)

            Form {
                Section(header: Text("Style")) {
                    Picker("Layout", selection: $contactTrickEntry.layout) {
                        ForEach(ContactTrickLayout.allCases, id: \.id) { layout in
                            Text(layout.displayName).tag(layout)
                        }
                    }
                    Toggle("Dark Mode", isOn: $contactTrickEntry.darkMode)
                }.listRowBackground(Color.chart)

                Section(header: Text("Display Values")) {
                    if contactTrickEntry.layout == .single {
                        Picker("Primary", selection: $contactTrickEntry.primary) {
                            ForEach(ContactTrickValue.allCases, id: \.id) { value in
                                Text(value.displayName).tag(value)
                            }
                        }
                    }

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
                }.listRowBackground(Color.chart)

                if contactTrickEntry.ring != .none {
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
                    }.listRowBackground(Color.chart)
                }

                // Font Settings Section
                Section(header: Text("Font Settings")) {
                    fontSizePicker
                    secondaryFontSizePicker
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
            NavigationStack {
                List {
                    Text("Lorem Ipsum Dolor Sit Amet")
                }
                .padding(.trailing, 10)
                .navigationBarTitle("Help", displayMode: .inline)

                Button { state.isHelpSheetPresented.toggle() }
                label: { Text("Got it!").frame(maxWidth: .infinity, alignment: .center) }
                    .buttonStyle(.bordered)
                    .padding(.top)
            }
            .padding()
            .presentationDetents(
                [.fraction(0.9), .large],
                selection: $state.helpSheetDetent
            )
        }
    }

    private func saveChanges() {
        Task {
            await state.updateContact(with: contactTrickEntry)
            dismiss()
        }
    }

    var stickySaveButton: some View {
        ZStack {
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
                .background(Color(.systemBlue))
                .tint(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(5)
        }
    }

    private var fontSizePicker: some View {
        Picker("Font Size", selection: $contactTrickEntry.fontSize) {
            ForEach(ContactTrickEntry.FontSize.allCases, id: \.self) { size in
                Text(size.displayName).tag(size)
            }
        }
    }

    private var secondaryFontSizePicker: some View {
        Picker("Secondary Font Size", selection: $contactTrickEntry.secondaryFontSize) {
            ForEach(ContactTrickEntry.FontSize.allCases, id: \.self) { size in
                Text(size.displayName).tag(size)
            }
        }
    }

    private var fontWeightPicker: some View {
        Picker("Font Weight", selection: $contactTrickEntry.fontWeight) {
            ForEach(
                [Font.Weight.light, Font.Weight.regular, Font.Weight.medium, Font.Weight.bold, Font.Weight.black],
                id: \.self
            ) { weight in
                Text("\(weight.displayName)".capitalized).tag(weight)
            }
        }
    }

    private var fontWidthPicker: some View {
        Picker("Font Width", selection: $contactTrickEntry.fontWidth) {
            ForEach(
                [Font.Width.standard, Font.Width.condensed, Font.Width.expanded],
                id: \.self
            ) { width in
                Text("\(width.displayName)".capitalized).tag(width)
            }
        }
    }
}
