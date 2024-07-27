import SwiftUI

struct SettingInputSection: View {
    enum InputType {
        case decimal
        case boolean
        case conditionalDecimal
    }

    @Binding var decimalValue: Decimal
    @Binding var booleanValue: Bool
    @Binding var shouldDisplayHint: Bool
    @Binding var selectedVerboseHint: String?

    var type: InputType
    var label: String
    var conditionalLabel: String?
    var miniHint: String
    var verboseHint: String
    var headerText: String?
    var footerText: String?
    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }

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
                                numberFormatter: formatter
                            )

                        }.padding(.top)
                    } else if type == .boolean {
                        HStack {
                            Toggle(isOn: $booleanValue) {
                                Text(label)
                            }
                        }
                    } else if type == .conditionalDecimal, let secondLabel = conditionalLabel {
                        HStack {
                            Toggle(isOn: $booleanValue) {
                                Text(label)
                            }
                        }.padding(.vertical)

                        if $booleanValue.wrappedValue {
                            HStack {
                                Text(secondLabel)

                                TextFieldWithToolBar(
                                    text: Binding(
                                        get: { decimalValue },
                                        set: { decimalValue = $0 }
                                    ),
                                    placeholder: decimalValue.description,
                                    numberFormatter: formatter
                                )
                            }.padding(.bottom)
                        }
                    }

                    HStack(alignment: .top) {
                        Text(miniHint)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                        Spacer()
                        Button(
                            action: {
                                shouldDisplayHint.toggle()
                                selectedVerboseHint = shouldDisplayHint ? verboseHint : nil
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
