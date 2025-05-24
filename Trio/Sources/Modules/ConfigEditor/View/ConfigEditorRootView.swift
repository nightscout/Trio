//
// Trio
// ConfigEditorRootView.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Marvin Polscheit on 2025-05-24.
// Most contributions by Ivan Valkou and Jon B Mårtensson.
//
// Documentation available under: https://triodocs.org/

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
