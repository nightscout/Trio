import LoopKitUI
import SwiftUI

struct DanaKitUserSettingsView: View {
    @ObservedObject var viewModel: DanaKitUserSettingsViewModel

    private var revervoirWarningView: PickerView {
        PickerView(
            value: Int(viewModel.lowReservoirRate),
            allowedOptions: Array(5 ... 40),
            formatter: { value in String(value) + LocalizedString("U", comment: "Insulin unit") },
            didChange: { value in viewModel.lowReservoirRate = UInt8(value) },
            title: LocalizedString("Low reservoir reminder", comment: "Text for low reservoir reminder"),
            description: LocalizedString(
                "The pump reminds you when the amount of insulin in the pump reaches this level",
                comment: "Description for low reservoir reminder"
            )
        )
    }

    private var time24hView: PickerView {
        PickerView(
            value: viewModel.isTimeDisplay24H ? 1 : 0,
            allowedOptions: [0, 1],
            formatter: { value in
                value == 1 ? LocalizedString("24h notation", comment: "24h notation") :
                    LocalizedString("12h notation", comment: "12h notation") },
            didChange: { value in viewModel.isTimeDisplay24H = value == 1 },
            title: LocalizedString("24h display", comment: "Text for 24h display"),
            description: LocalizedString("Should time be display in 12h or 24h", comment: "Description for 24h display")
        )
    }

    private var buttonScrollOnOffView: PickerView {
        PickerView(
            value: viewModel.isButtonScrollOnOff ? 1 : 0,
            allowedOptions: [0, 1],
            formatter: { value in
                value == 1 ? LocalizedString("On", comment: "text on") : LocalizedString("Off", comment: "text off") },
            didChange: { value in viewModel.isButtonScrollOnOff = value == 1 },
            title: LocalizedString("Scroll function", comment: "Text for Scroll function")
        )
    }

    private var backlightOnTimeInSecView: PickerView {
        PickerView(
            value: Int(viewModel.backlightOnTimeInSec),
            allowedOptions: Array(0 ... 48).map({ $0 * 5 }),
            formatter: { value in "\(value) \(LocalizedString("sec", comment: "text for second"))" },
            didChange: { value in viewModel.backlightOnTimeInSec = UInt8(value) },
            title: LocalizedString("Backlight on time", comment: "backlightOnTime")
        )
    }

    private var lcdOnTimeInSecView: PickerView {
        PickerView(
            value: Int(viewModel.lcdOnTimeInSec),
            allowedOptions: Array(0 ... 48).map({ $0 * 5 }),
            formatter: { value in "\(value) \(LocalizedString("sec", comment: "text for second"))" },
            didChange: { value in viewModel.lcdOnTimeInSec = UInt8(value) },
            title: LocalizedString("Lcd on time", comment: "lcdOnTime")
        )
    }

    private var beepAlarmView: PickerView {
        PickerView(
            value: Int(viewModel.beepAndAlarm.rawValue),
            allowedOptions: BeepAlarmType.all(),
            formatter: beepFormatter,
            didChange: { value in viewModel.beepAndAlarm = BeepAlarmType(rawValue: UInt8(value)) ?? .sound },
            title: LocalizedString("Alarm beeps", comment: "beepAndAlarm")
        )
    }

    private var refillAmountView: PickerView {
        PickerView(
            value: Int(viewModel.refillAmount),
            allowedOptions: Array(0 ... 60).map({ $0 * 5 }),
            formatter: { value in "\(value) \(LocalizedString("U", comment: "Insulin unit")) " },
            didChange: { value in viewModel.refillAmount = UInt16(value) },
            title: LocalizedString("Refill amount", comment: "refillAmount")
        )
    }

    @ViewBuilder var body: some View {
        VStack {
            List {
                NavigationLink(destination: revervoirWarningView) {
                    HStack {
                        Text(LocalizedString("Low reservoir reminder", comment: "Text for low reservoir reminder"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(String(viewModel.lowReservoirRate) + LocalizedString("U", comment: "Insulin unit"))
                    }
                }
                NavigationLink(destination: time24hView) {
                    HStack {
                        Text(LocalizedString("24h display", comment: "Text for 24h display"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(
                            viewModel
                                .isTimeDisplay24H ? LocalizedString("24h notation", comment: "24h notation") :
                                LocalizedString("12h notation", comment: "12h notation")
                        )
                    }
                }
                NavigationLink(destination: buttonScrollOnOffView) {
                    HStack {
                        Text(LocalizedString("Scroll function", comment: "Text for Scroll function"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(
                            viewModel
                                .isButtonScrollOnOff ? LocalizedString("On", comment: "text on") :
                                LocalizedString("Off", comment: "text off")
                        )
                    }
                }
                NavigationLink(destination: backlightOnTimeInSecView) {
                    HStack {
                        Text(LocalizedString("Backlight on time", comment: "backlightOnTime"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text("\(viewModel.backlightOnTimeInSec) \(LocalizedString("sec", comment: "text for second"))")
                    }
                }
                NavigationLink(destination: lcdOnTimeInSecView) {
                    HStack {
                        Text(LocalizedString("Lcd on time", comment: "lcdOnTime"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text("\(viewModel.lcdOnTimeInSec) \(LocalizedString("sec", comment: "text for second"))")
                    }
                }
                NavigationLink(destination: beepAlarmView) {
                    HStack {
                        Text(LocalizedString("Alarm beeps", comment: "beepAndAlarm"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(beepFormatter(value: Int(viewModel.beepAndAlarm.rawValue)))
                    }
                }
                NavigationLink(destination: refillAmountView) {
                    HStack {
                        Text(LocalizedString("Refill amount", comment: "refillAmount"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(String(viewModel.refillAmount) + LocalizedString("U", comment: "Insulin unit"))
                    }
                }
            }
            Spacer()

            ContinueButton(
                text: LocalizedString("Save", comment: "Text for save button"),
                loading: $viewModel.storingUseroption,
                action: { viewModel.storeUserOption() }
            )
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarTitle(LocalizedString("User options", comment: "Title for user options"))
    }

    private func beepFormatter(value: Int) -> String {
        switch value {
        case 1:
            return LocalizedString("Sound", comment: "beepAndAlarm.sound")
        case 2:
            return LocalizedString("Vibration", comment: "beepAndAlarm.vibration")
        case 3:
            return LocalizedString("Both", comment: "beepAndAlarm.both")
        default:
            return ""
        }
    }
}

#Preview {
    DanaKitUserSettingsView(viewModel: DanaKitUserSettingsViewModel(nil))
}
