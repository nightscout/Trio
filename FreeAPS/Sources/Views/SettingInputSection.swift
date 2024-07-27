import SwiftUI

struct SettingInputSection: View {
    enum InputType {
        case decimal
        case boolean
    }

    @Binding var decimalValue: Decimal
    @Binding var booleanValue: Bool
    @Binding var showHint: Bool
    @Binding var selectedVerboseHint: String?

    var type: InputType
    var label: String
    var shortHint: String
    var verboseHint: String
    var headerText: String?
    var footerText: String?

    var body: some View {
        Section(
            content: {
                VStack {
                    if type == .decimal {
                        HStack {
                            Text(label)

                            TextFieldWithToolBar(
                                text: Binding(
                                    get: { decimalValue },
                                    set: { decimalValue = $0 }
                                ),
                                placeholder: decimalValue.description,
                                numberFormatter: NumberFormatter()
                            )

                        }.padding(.top)
                    } else if type == .boolean {
                        HStack {
                            Toggle(isOn: $booleanValue) {
                                Text(label)
                            }
                        }
                    }

                    HStack(alignment: .top) {
                        Text(shortHint)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                        Spacer()
                        Button(
                            action: {
                                showHint.toggle()
                                selectedVerboseHint = showHint ? verboseHint : nil
                            },
                            label: {
                                HStack {
                                    Image(systemName: "questionmark.circle")
                                }
                            }
                        )
                    }.padding(type == .boolean ? .vertical : .bottom)
                }
            },
            header: {
                if let headerText = headerText {
                    Text(headerText)
                }
            },
            footer: {
                if let footerText = footerText {
                    Text(footerText)
                }
            }
        ).listRowBackground(Color.chart)
    }
}
