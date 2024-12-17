import Contacts
import ContactsUI
import SwiftUI
import Swinject

extension ContactTrick {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State private var isAddSheetPresented: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            Form {
                contactTrickList
            }
            .onAppear(perform: configureView)
            .navigationTitle("Contacts Configuration")
            .navigationBarTitleDisplayMode(.large)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        isAddSheetPresented.toggle()
                    }) {
                        HStack {
                            Text("Add Contact")
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $isAddSheetPresented) {
                AddContactTrickSheet(state: state)
            }
        }

        private var contactTrickList: some View {
            List {
                if state.contactTrickEntries.isEmpty {
                    Section(
                        header: Text(""),
                        content: {
                            Text("No Contact Trick Entries.")
                        }
                    ).listRowBackground(Color.chart)
                } else {
                    ForEach(state.contactTrickEntries, id: \.id) { entry in
                        NavigationLink(destination: ContactTrickDetailView(entry: entry, state: state)) {
                            HStack {
                                ZStack {
                                    Circle()
                                        .fill(entry.darkMode ? .black : .white)
                                        .foregroundColor(.white)
                                        .frame(width: 40, height: 40)

                                    Image(uiImage: ContactPicture.getImage(contact: entry, state: state.state))
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())

                                    Circle()
                                        .stroke(lineWidth: 2)
                                        .foregroundColor(.white)
                                        .frame(width: 40, height: 40)
                                }

                                Text("\(entry.name)")
                            }
                        }
                    }
                    .onDelete(perform: onDelete)
                }
            }.listRowBackground(Color.chart)
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
