import Contacts
import ContactsUI
import SwiftUI
import Swinject

extension ContactTrick {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var contactStore = CNContactStore()
        @State private var authorization = CNContactStore.authorizationStatus(for: .contacts)

        var body: some View {
            Form {
                switch authorization {
                case .authorized:
                    Section(header: Text("Contacts")) {
                        list
                        addButton
                    }
                    Section(
                        header: state.changed ?
                            Text("Don't forget to save your changes.")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundStyle(.primary) : nil
                    ) {
                        HStack {
                            if state.syncInProgress {
                                ProgressView().padding(.trailing, 10)
                            }
                            Button { state.save() }
                            label: {
                                Text(state.syncInProgress ? "Saving..." : "Save")
                            }
                            .disabled(state.syncInProgress || !state.changed)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }

                case .notDetermined:
                    Section {
                        Text(
                            "Trio needs access to your contacts for this feature to work"
                        )
                    }
                    Section {
                        Button(action: onRequestContactsAccess) {
                            Text("Grant Trio access to contacts")
                        }
                    }

                case .denied:
                    Section {
                        Text(
                            "Access to contacts denied"
                        )
                    }

                case .restricted:
                    Section {
                        Text(
                            "Access to contacts is restricted (parental control?)"
                        )
                    }

                case .limited:
                    Section {
                        Text(
                            "Access to contacts is limited. Trio needs full access to contacts for this feature to work"
                        )
                    }
                @unknown default:
                    Section {
                        Text(
                            "Access to contacts - unknown state"
                        )
                    }
                }

                Section {}
                footer: {
                    Text(
                        "A Contact Image can be used to get live updates from Trio to your Apple Watch Contact complication and/or your iPhone Contact widget."
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear(perform: configureView)
            .navigationTitle("Contact Image")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(
                trailing: EditButton()
            )
        }

        private func contactSettings(for index: Int) -> some View {
            EntryView(entry: Binding(
                get: { state.items[index].entry },
                set: { newValue in state.update(index, newValue) }
            ), previewState: previewState)
        }

        var previewState: ContactTrickState {
            let units = state.units

            return ContactTrickState(
                glucose: units == .mmolL ? "6,8" : "127",
                trend: "↗︎",
                delta: units == .mmolL ? "+0,3" : "+7",
                lastLoopDate: .now,
                iob: 6.1,
                iobText: "6,1",
                cob: 27.0,
                cobText: "27",
                eventualBG: units == .mmolL ? "8,9" : "163",
                maxIOB: 12.0,
                maxCOB: 120.0
            )
        }

        private var list: some View {
            List {
                ForEach(state.items.indexed(), id: \.1.id) { index, item in
                    NavigationLink(destination: contactSettings(for: index)) {
                        EntryListView(entry: .constant(item.entry), index: .constant(index), previewState: previewState)
                    }
                    .moveDisabled(true)
                }
                .onDelete(perform: onDelete)
            }
        }

        private var addButton: some View {
            AnyView(Button(action: onAdd) { Text("Add") })
        }

        func onAdd() {
            state.add()
        }

        func onRequestContactsAccess() {
            contactStore.requestAccess(for: .contacts) { _, _ in
                DispatchQueue.main.async {
                    authorization = CNContactStore.authorizationStatus(for: .contacts)
                }
            }
        }

        private func onDelete(offsets: IndexSet) {
            state.remove(atOffsets: offsets)
        }
    }

    struct EntryListView: View {
        @Binding var entry: ContactTrickEntry
        @Binding var index: Int
        @State private var refreshKey = UUID()
        let previewState: ContactTrickState

        var body: some View {
            HStack {
                Text(
                    NSLocalizedString("Contact", comment: "") + ": " + "Trio \(index + 1)"
                )
                .font(.body)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

                Spacer()

                VStack {
                    GeometryReader { geometry in
                        ZStack {
                            Circle()
                                .fill(entry.darkMode ? .black : .white)
                                .foregroundColor(.white)
                            Image(uiImage: ContactPicture.getImage(contact: entry, state: previewState))
                                .resizable()
                                .aspectRatio(1, contentMode: .fit)
                                .frame(width: geometry.size.height, height: geometry.size.height)
                                .clipShape(Circle())
                            Circle()
                                .stroke(lineWidth: 2)
                                .foregroundColor(.white)
                        }
                        .frame(width: geometry.size.height, height: geometry.size.height)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 30)
            }
            .frame(maxWidth: .infinity)
        }
    }

    struct EntryView: View {
        @Binding var entry: ContactTrickEntry
        @State private var availableFonts: [String]? = nil
        let previewState: ContactTrickState

        private let ringWidths: [Int] = [5, 10, 15]
        private let ringGaps: [Int] = [0, 2, 4]

        var body: some View {
            VStack {
                Section {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(entry.darkMode ? .black : .white)
                            Image(uiImage: ContactPicture.getImage(contact: entry, state: previewState))
                                .resizable()
                                .aspectRatio(1, contentMode: .fit)
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                            Circle()
                                .stroke(lineWidth: 2)
                                .foregroundColor(.white)
                        }
                        .frame(width: 64, height: 64)
                    }
                }

                Form {
                    Section {
                        Picker(
                            selection: $entry.layout,
                            label: Text("Layout")
                        ) {
                            ForEach(ContactTrickLayout.allCases, id: \.self) { layout in
                                Text(layout.displayName).tag(layout)
                            }
                        }
                    }

                    layoutSpecificSection

                    Section(header: Text("Ring")) {
                        Picker(
                            selection: $entry.ring1,
                            label: Text("Outer")
                        ) {
                            ForEach(ContactTrickLargeRing.allCases, id: \.self) { ring in
                                Text(ring.displayName).tag(ring)
                            }
                        }
                        Picker(
                            selection: $entry.ringWidth,
                            label: Text("Width")
                        ) {
                            ForEach(ringWidths, id: \.self) { width in
                                Text("\(width)").tag(width)
                            }
                        }
                        Picker(
                            selection: $entry.ringGap,
                            label: Text("Gap")
                        ) {
                            ForEach(ringGaps, id: \.self) { gap in
                                Text("\(gap)").tag(gap)
                            }
                        }
                    }

                    Section(header: Text("Font")) {
                        Picker(
                            selection: $entry.fontSize,
                            label: Text("Size")
                        ) {
                            ForEach(
                                [
                                    ContactTrickEntry.fontSize.tiny,
                                    ContactTrickEntry.fontSize.small,
                                    ContactTrickEntry.fontSize.regular,
                                    ContactTrickEntry.fontSize.large
                                ],
                                id: \.self
                            ) { size in
                                Text("\(size)").tag(size)
                            }
                        }
                        Picker(
                            selection: $entry.secondaryFontSize,
                            label: Text("Secondary size")
                        ) {
                            ForEach(
                                [
                                    ContactTrickEntry.fontSize.tiny,
                                    ContactTrickEntry.fontSize.small,
                                    ContactTrickEntry.fontSize.regular,
                                    ContactTrickEntry.fontSize.large
                                ],
                                id: \.self
                            ) { size in
                                Text("\(size)").tag(size)
                            }
                        }
                        Picker(
                            selection: $entry.fontWidth,
                            label: Text("Tracking")
                        ) {
                            ForEach(
                                [Font.Width.standard, Font.Width.condensed, Font.Width.expanded],
                                id: \.self
                            ) { width in
                                Text(width.displayName).tag(width)
                            }
                        }
                        Picker(
                            selection: $entry.fontWeight,
                            label: Text("Weight")
                        ) {
                            ForEach(
                                [Font.Weight.regular, Font.Weight.bold, Font.Weight.black],
                                id: \.self
                            ) { weight in
                                Text(weight.displayName).tag(weight)
                            }
                        }
                    }

                    Section {
                        Toggle("Dark mode", isOn: $entry.darkMode)
                    }
                }
            }
        }

        private var layoutSpecificSection: some View {
            Section {
                if entry.layout == .single {
                    Picker(
                        selection: $entry.primary,
                        label: Text("Primary")
                    ) {
                        ForEach(ContactTrickValue.allCases, id: \.self) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    Picker(
                        selection: $entry.top,
                        label: Text("Top")
                    ) {
                        ForEach(ContactTrickValue.allCases, id: \.self) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    Picker(
                        selection: $entry.bottom,
                        label: Text("Bottom")
                    ) {
                        ForEach(ContactTrickValue.allCases, id: \.self) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                } else if entry.layout == .split {
                    Picker(
                        selection: $entry.top,
                        label: Text("Top")
                    ) {
                        ForEach(ContactTrickValue.allCases, id: \.self) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    Picker(
                        selection: $entry.bottom,
                        label: Text("Bottom")
                    ) {
                        ForEach(ContactTrickValue.allCases, id: \.self) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                }
            }
        }
    }
}

extension Font.Width {
    var displayName: String {
        switch self {
        case .condensed: return "Condensed"
        case .expanded: return "Expanded"
        case .compressed: return "Compressed"
        case .standard: return "Standard"
        default: return "Unknown"
        }
    }
}

extension Font.Weight {
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .regular: return "Regular"
        case .medium: return "Medium"
        case .bold: return "Bold"
        default: return "Unknown"
        }
    }
}
