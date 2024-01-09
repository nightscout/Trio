import SwiftUI
import Swinject

extension ConfigEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        let file: String
        @StateObject var state = StateModel()
        @State private var showShareSheet = false

        @Environment(\.colorScheme) var colorScheme
        var color: LinearGradient {
            colorScheme == .dark ? LinearGradient(
                gradient: Gradient(colors: [
                    Color.bgDarkBlue,
                    Color.bgDarkerDarkBlue
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
                :
                LinearGradient(
                    gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
        }

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
                    .navigationBarTitleDisplayMode(.inline)
                    .padding()
            }
            .scrollContentBackground(.hidden).background(color)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    typealias Callback = (_ activityType: UIActivity.ActivityType?, _ completed: Bool, _ returnedItems: [Any]?, _ error: Error?)
        -> Void

    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    let excludedActivityTypes: [UIActivity.ActivityType]? = nil
    let callback: Callback? = nil

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        controller.excludedActivityTypes = excludedActivityTypes
        controller.completionWithItemsHandler = callback
        return controller
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {
        // nothing to do here
    }
}
