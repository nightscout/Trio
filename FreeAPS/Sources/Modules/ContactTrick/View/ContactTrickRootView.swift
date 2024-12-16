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
                contactTrickList
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

        private var contactTrickList: some View {
            List {
                ForEach(state.contactTrickEntries, id: \.id) { entry in
                    NavigationLink(destination: ContactTrickDetailView(entry: entry, state: state)) {
                        HStack {
                            // TODO: - make this beautiful @Dan
                            ZStack {
                                Circle()
                                    .fill(entry.darkMode ? .black : .white)
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)

                                Image(uiImage: ContactPicture.getImage(contact: entry, state: state.previewState))
                                    .resizable()
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())

                                Circle()
                                    .stroke(lineWidth: 2)
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                            }

                            // Entry name
                            Text("\(entry.name)")
                        }
                    }
                }
                .onDelete(perform: onDelete)
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
