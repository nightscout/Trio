import Charts
import SwiftUI
import Swinject

extension BasalProfileEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()

        private var rateFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        var fullScheduleWarning: some View {
            VStack {
                Text(
                    "Basal profile covers 24 hours. You cannot add more rates. Please remove or adjust existing rates to make space."
                ).bold()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.tabBar)
            .clipShape(
                .rect(
                    topLeadingRadius: 10,
                    bottomLeadingRadius: 10,
                    bottomTrailingRadius: 10,
                    topTrailingRadius: 10
                )
            )
        }

        var totalBasalRow: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Total")
                        .bold()

                    Spacer()

                    HStack {
                        Text(rateFormatter.string(from: state.total as NSNumber) ?? "0")
                        Text("U/day")
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .padding()
            .background(Color.chart.opacity(0.65))
            .cornerRadius(10)
            .padding([.horizontal, .top])
        }

        var body: some View {
            TherapySettingsEditor.RootView(
                state: state,
                configureView: configureView,
                chartColor: Color.purple,
                headerContent: {
                    if !state.canAdd {
                        fullScheduleWarning
                            .padding()
                    }
                },
                footerContent: {
                    if !state.items.isEmpty {
                        totalBasalRow
                    }
                }
            )
            .alert(isPresented: $state.showAlert) {
                Alert(
                    title: Text("Unable to Save"),
                    message: Text("Trio could not communicate with your pump. Changes to your basal profile were not saved."),
                    dismissButton: .default(Text("Close"))
                )
            }
            .navigationTitle("Basal Rates")
        }
    }
}
