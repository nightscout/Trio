import SwiftUI
import Swinject

extension ConfigEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        let file: String
        @StateObject var state = StateModel()
        @State private var showShareSheet = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            ZStack {
                TextEditor(text: $state.configText)
                    .keyboardType(.asciiCapable)
                    .font(.system(.subheadline, design: .monospaced))
                    .allowsTightening(true)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .toolbar {
                        ToolbarItemGroup(placement: .bottomBar) {
                            Spacer()
                            Button { showShareSheet = true }
                            label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                    .navigationBarItems(
                        trailing: Button("Save", action: state.save)
                    )
                    .sheet(isPresented: $showShareSheet) {
                        ShareSheet(activityItems: [state.provider.urlFor(file: state.file)!])
                    }
                    .onAppear {
                        configureView {
                            state.file = file
                        }
                    }
                    .navigationTitle(file)
                    .navigationBarTitleDisplayMode(.automatic)
                    .padding()
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
        }
    }
}
