import SwiftUI

struct CustomDatePicker: UIViewRepresentable {
    @Binding var selection: Date

    // Coordinator to handle date changes
    class Coordinator: NSObject {
        var parent: CustomDatePicker

        init(_ parent: CustomDatePicker) {
            self.parent = parent
        }

        @objc func dateChanged(_ sender: UIDatePicker) {
            let calendar = Calendar.current
            // Set the time of the selected date to 23:59:59 for any selected date
            if let adjustedDate = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: sender.date) {
                parent.selection = adjustedDate
            } else {
                parent.selection = sender.date // Fallback in case something goes wrong
            }
        }
    }

    func makeUIView(context: Context) -> UIDatePicker {
        let datePicker = UIDatePicker()
        datePicker.datePickerMode = .date

        // Calculate yesterday's date at 23:59:59
        let today = Date()
        let calendar = Calendar.current
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           let adjustedYesterday = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: yesterday)
        {
            datePicker.maximumDate = adjustedYesterday // Set maximum date to yesterday at 23:59:59
            datePicker.date = adjustedYesterday // Set default date to yesterday at 23:59:59
        }

        // Set up the date change action
        datePicker.addTarget(context.coordinator, action: #selector(Coordinator.dateChanged(_:)), for: .valueChanged)

        return datePicker
    }

    func updateUIView(_ uiView: UIDatePicker, context _: Context) {
        // Ensure the displayed date is also adjusted to 23:59:59
        let calendar = Calendar.current
        if let adjustedDate = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: selection) {
            uiView.date = adjustedDate
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}
