import SwiftUI

struct AddContactTrickSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    @ObservedObject var state: ContactTrick.StateModel

    @State private var hasHighContrast: Bool = true
    @State private var ringWidth: ContactTrickEntry.RingWidth = .regular
    @State private var ringGap: ContactTrickEntry.RingGap = .small
    @State private var layout: ContactTrickLayout = .default
    @State private var primary: ContactTrickValue = .glucose
    @State private var top: ContactTrickValue = .none
    @State private var bottom: ContactTrickValue = .trend
    @State private var ring: ContactTrickLargeRing = .none
    @State private var fontSize: ContactTrickEntry.FontSize = .regular
    @State private var secondaryFontSize: ContactTrickEntry.FontSize = .small
    @State private var fontWeight: Font.Weight = .medium
    @State private var fontWidth: Font.Width = .standard

    private var previewEntry: ContactTrickEntry {
        ContactTrickEntry(
            id: UUID(),
            name: "", // automatically set and populated
            layout: layout,
            ring: ring,
            primary: primary,
            top: top,
            bottom: bottom,
            contactId: nil, // not needed for preview, gets set later in ContactTrickStateModel via ContactTrickManager
            hasHighContrast: hasHighContrast,
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
            VStack {
                // Preview Section
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(previewEntry.hasHighContrast ? .black : .white)
                            .foregroundColor(.white)
                            .frame(width: 100, height: 100)
                        Image(uiImage: ContactPicture.getImage(contact: previewEntry, state: state.state))
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
                .padding(.top, 40)
                .padding(.bottom)

                Form {
                    // Layout Section
                    Section(header: Text("Style")) {
                        Picker("Layout", selection: $layout) {
                            ForEach(ContactTrickLayout.allCases, id: \.id) { layout in
                                Text(layout.displayName).tag(layout)
                            }
                        }.onChange(of: layout, { oldLayout, newLayout in
                            if oldLayout != newLayout, newLayout == .split {
                                top = .glucose
                            } else {
                                top = .none
                            }
                        })
                        Toggle("High Contrast Mode", isOn: $hasHighContrast)
                    }.listRowBackground(Color.chart)

                    // Primary Value Section
                    Section(header: Text("Display Values")) {
                        Picker("Top Value", selection: $top) {
                            ForEach(ContactTrickValue.allCases, id: \.id) { value in
                                Text(value.displayName).tag(value)
                            }
                        }
                        if layout == .default {
                            Picker("Primary", selection: $primary) {
                                ForEach(ContactTrickValue.allCases, id: \.id) { value in
                                    Text(value.displayName).tag(value)
                                }
                            }
                        }
                        Picker("Bottom Value", selection: $bottom) {
                            ForEach(ContactTrickValue.allCases, id: \.id) { value in
                                Text(value.displayName).tag(value)
                            }
                        }

                    }.listRowBackground(Color.chart)

                    // Ring Settings Section
                    Section(header: Text("Ring Settings")) {
                        Picker("Ring Type", selection: $ring) {
                            ForEach(ContactTrickLargeRing.allCases, id: \.self) { ring in
                                Text(ring.displayName).tag(ring)
                            }
                        }

                        if ring != .none {
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
                    }.listRowBackground(Color.chart)

                    // Font Settings Section
                    Section(header: Text("Font Settings")) {
                        fontSizePicker
                        if layout == .split {
                            secondaryFontSizePicker
                        }
                        fontWeightPicker
                        fontWidthPicker
                    }.listRowBackground(Color.chart)
                }

                stickySaveButton
            }
            .navigationTitle("Add Contact Items")
            .navigationBarTitleDisplayMode(.inline)
            .listSectionSpacing(10)
            .padding(.top, 30)
            .ignoresSafeArea(edges: .top)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
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
                saveNewEntry()
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
                Text("\(weight.displayName)".capitalized).tag(weight)
            }
        }
    }

    private var fontWidthPicker: some View {
        Picker("Font Width", selection: $fontWidth) {
            ForEach(
                [Font.Width.standard, Font.Width.expanded],
                id: \.self
            ) { width in
                Text("\(width.displayName)".capitalized).tag(width)
            }
        }
    }

    private func saveNewEntry() {
        // Save the currently previewed entry
        Task {
            await state.createAndSaveContactTrick(entry: previewEntry, name: "Trio \(state.contactTrickEntries.count + 1)")
            dismiss()
        }
    }
}
