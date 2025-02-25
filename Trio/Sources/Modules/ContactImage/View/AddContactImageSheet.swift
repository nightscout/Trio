import SwiftUI

struct AddContactImageSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    @ObservedObject var state: ContactImage.StateModel

    @State private var contactName: String = ""
    @State private var hasHighContrast: Bool = true
    @State private var ringWidth: ContactImageEntry.RingWidth = .regular
    @State private var ringGap: ContactImageEntry.RingGap = .small
    @State private var layout: ContactImageLayout = .default
    @State private var primary: ContactImageValue = .glucose
    @State private var top: ContactImageValue = .none
    @State private var bottom: ContactImageValue = .trend
    @State private var ring: ContactImageLargeRing = .none
    @State private var fontSize: ContactImageEntry.FontSize = .regular
    @State private var secondaryFontSize: ContactImageEntry.FontSize = .small
    @State private var fontWeight: Font.Weight = .medium
    @State private var fontWidth: Font.Width = .standard

    private var previewEntry: ContactImageEntry {
        ContactImageEntry(
            id: UUID(),
            name: contactName, // automatically set and populated
            layout: layout,
            ring: ring,
            primary: primary,
            top: top,
            bottom: bottom,
            contactId: nil, // not needed for preview, gets set later in ContactImageStateModel via ContactImageManager
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
                            .fill(.black)
                            .foregroundColor(.white)
                            .frame(width: 100, height: 100)
                        Image(uiImage: ContactPicture.getImage(contact: previewEntry, state: state.state))
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
                .padding(.top, 40)
                .padding(.bottom)

                Form {
                    Section(
                        header: Text("Contact Name"),
                        content: {
                            TextField("Enter Name (Optional)", text: $contactName)
                        }
                    ).listRowBackground(Color.chart)

                    // Layout Section
                    Section(header: Text("Style")) {
                        Picker("Layout", selection: $layout) {
                            ForEach(ContactImageLayout.allCases, id: \.id) { layout in
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
                            ForEach(ContactImageValue.allCases, id: \.id) { value in
                                Text(value.displayName).tag(value)
                            }
                        }
                        if layout == .default {
                            Picker("Primary", selection: $primary) {
                                ForEach(ContactImageValue.allCases, id: \.id) { value in
                                    Text(value.displayName).tag(value)
                                }
                            }
                        }
                        Picker("Bottom Value", selection: $bottom) {
                            ForEach(ContactImageValue.allCases, id: \.id) { value in
                                Text(value.displayName).tag(value)
                            }
                        }

                    }.listRowBackground(Color.chart)

                    // Ring Settings Section
                    Section(header: Text("Ring Settings")) {
                        Picker("Ring Type", selection: $ring) {
                            ForEach(ContactImageLargeRing.allCases, id: \.self) { ring in
                                Text(ring.displayName).tag(ring)
                            }
                        }

                        if ring != .none {
                            Picker("Ring Width", selection: $ringWidth) {
                                ForEach(ContactImageEntry.RingWidth.allCases, id: \.self) { width in
                                    Text(width.displayName).tag(width)
                                }
                            }
                            Picker("Ring Gap", selection: $ringGap) {
                                ForEach(ContactImageEntry.RingGap.allCases, id: \.self) { gap in
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
                ContactImageHelpView(state: state, helpSheetDetent: $state.helpSheetDetent)
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
            ForEach(ContactImageEntry.FontSize.allCases, id: \.self) { size in
                Text(size.displayName).tag(size)
            }
        }
    }

    private var secondaryFontSizePicker: some View {
        Picker("Secondary Font Size", selection: $secondaryFontSize) {
            ForEach(ContactImageEntry.FontSize.allCases, id: \.self) { size in
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
            await state.createAndSaveContactImage(
                entry: previewEntry,
                name: contactName.isEmpty ? "Trio \(state.contactImageEntries.count + 1)" : contactName
            )
            dismiss()
        }
    }
}
