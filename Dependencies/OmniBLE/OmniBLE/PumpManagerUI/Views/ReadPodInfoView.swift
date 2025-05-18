//
//  ReadPodInfoView.swift
//  OmniBLE
//
//  Created by Joe Moran on 11/25/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit


struct ReadPodInfoView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    var title: String           // e.g., "Read Pulse Log"
    var actionString: String    // e.g., "Reading Pulse Log..."
    var failedString: String    // e.g., "Failed to read pulse log."

    var toRun: ((_ completion: @escaping (_ result: Result<String, Error>) -> Void) -> Void)?

    @State private var alertIsPresented: Bool = false
    @State private var displayString: String = ""
    @State private var error: Error? = nil
    @State private var executing: Bool = false
    @State private var showActivityView: Bool = false

    var body: some View {
        VStack {
            List {
                Section {
                    let myFont = Font
                        .system(size: 12)
                        .monospaced()
                    Text(self.displayString)
                        .font(myFont)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        self.showActivityView = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }.sheet(isPresented: $showActivityView) {
                ActivityView(isPresented: $showActivityView, activityItems: [self.displayString])
            }
            VStack {
                Button(action: {
                    asyncAction()
                }) {
                    Text(buttonText)
                        .actionButtonStyle(.primary)
                }
                .padding()
                .disabled(executing)
            }
            .padding(self.horizontalSizeClass == .regular ? .bottom : [])
            .background(Color(UIColor.secondarySystemGroupedBackground).shadow(radius: 5))
        }
        .insetGroupedListStyle()
        .navigationTitle(title)
         .navigationBarTitleDisplayMode(.automatic)
        .alert(isPresented: $alertIsPresented, content: { alert(error: error) })
        .onFirstAppear {
            asyncAction()
        }
    }

    private func asyncAction () {
        DispatchQueue.global(qos: .utility).async {
            executing = true
            self.displayString = ""
            toRun?() { (result) in
                executing = false
                switch result {
                case .success(let resultString):
                    self.displayString = resultString
                case .failure(let error):
                    self.displayString = ""
                    self.error = error
                    self.alertIsPresented = true
                }
            }
        }
    }

    private var buttonText: String {
        if executing {
            return actionString
        } else {
            return title
        }
    }

    private func alert(error: Error?) -> SwiftUI.Alert {
        return SwiftUI.Alert(
            title: Text(failedString),
            message: Text(error?.localizedDescription ?? "No Error")
        )
    }
}

struct ReadPodInfoView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ReadPodInfoView(
                title: "Read Pulse Log",
                actionString: "Reading Pulse Log...",
                failedString: "Failed to read pulse log"
            ) { completion in
                let podInfoPulseLogRecent = try! PodInfoPulseLogRecent(encodedData: Data([0x50, 0x03, 0x17,
                    0x39, 0x72, 0x58, 0x01,  0x3c, 0x72, 0x43, 0x01,  0x41, 0x72, 0x5a, 0x01,  0x44, 0x71, 0x47, 0x01,
                    0x49, 0x51, 0x59, 0x01,  0x4c, 0x51, 0x44, 0x01,  0x51, 0x73, 0x59, 0x01,  0x54, 0x50, 0x43, 0x01,
                    0x59, 0x50, 0x5a, 0x81,  0x5c, 0x51, 0x42, 0x81,  0x61, 0x73, 0x59, 0x81,  0x00, 0x75, 0x43, 0x80,
                    0x05, 0x70, 0x5a, 0x80,  0x08, 0x50, 0x44, 0x80,  0x0d, 0x50, 0x5b, 0x80,  0x10, 0x75, 0x43, 0x80,
                    0x15, 0x72, 0x5e, 0x80,  0x18, 0x73, 0x45, 0x80,  0x1d, 0x72, 0x5b, 0x00,  0x20, 0x70, 0x43, 0x00,
                    0x25, 0x50, 0x5c, 0x00,  0x28, 0x50, 0x46, 0x00,  0x2d, 0x50, 0x5a, 0x00,  0x30, 0x75, 0x47, 0x00,
                    0x35, 0x72, 0x59, 0x00,  0x38, 0x70, 0x46, 0x00,  0x3d, 0x75, 0x57, 0x00,  0x40, 0x72, 0x43, 0x00,
                    0x45, 0x73, 0x55, 0x00,  0x48, 0x73, 0x41, 0x00,  0x4d, 0x70, 0x52, 0x00,  0x50, 0x73, 0x3f, 0x00,
                    0x55, 0x74, 0x4d, 0x00,  0x58, 0x72, 0x3d, 0x80,  0x5d, 0x73, 0x4d, 0x80,  0x60, 0x71, 0x3d, 0x80,
                    0x01, 0x51, 0x50, 0x80,  0x04, 0x72, 0x3d, 0x80,  0x09, 0x50, 0x4e, 0x80,  0x0c, 0x51, 0x40, 0x80,
                    0x11, 0x74, 0x50, 0x80,  0x14, 0x71, 0x40, 0x80,  0x19, 0x50, 0x4d, 0x80,  0x1c, 0x75, 0x3f, 0x00,
                    0x21, 0x72, 0x52, 0x00,  0x24, 0x72, 0x40, 0x00,  0x29, 0x71, 0x53, 0x00,  0x2c, 0x50, 0x42, 0x00,
                    0x31, 0x51, 0x55, 0x00,  0x34, 0x50, 0x42, 0x00   ]))
                let lastPulseNumber = Int(podInfoPulseLogRecent.indexLastEntry)
                completion(.success(pulseLogString(pulseLogEntries: podInfoPulseLogRecent.pulseLog, lastPulseNumber: lastPulseNumber)))
            }
        }
    }
}
