import SwiftUI
import Swinject

extension AppleHealthKit {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            Form {
                Section {
                    Toggle("Connect to Apple Health", isOn: $state.useAppleHealth)
                    HStack {
                        Image(systemName: "pencil.circle.fill")
                        Text(
                            "This allows Trio to read from and write to Apple Heath. You must also give permissions in Settings > Health > Data Access. If you enter a glucose value into Apple Health, open Trio to confirm it shows up."
                        )
                        .font(.caption)
                    }
                    .foregroundColor(Color.secondary)
                    if state.needShowInformationTextForSetPermissions {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text("For write data to Apple Health you must give permissions in Settings > Health > Data Access")
                                .font(.caption)
                        }
                        .foregroundColor(Color.secondary)
                    }
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
