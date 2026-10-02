import SwiftUI

struct StatSelectionPopover<Content: View>: View {
    let selectedDate: Date
    let selectedInterval: Stat.StateModel.StatsTimeInterval
    let tint: Color
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    private var selectionTitle: String {
        let dayText = selectedDate.formatted(.dateTime.month().day().weekday())
        if selectedInterval == .day {
            let hourRange = selectedDate.formatted(.dateTime.hour()) + "-" +
                Calendar.current.date(byAdding: .hour, value: 1, to: selectedDate)!
                .formatted(.dateTime.hour())
            return dayText + "\n" + hourRange
        }
        return dayText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectionTitle)
                .font(.subheadline).bold().foregroundStyle(Color.secondary)
            content()
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.bgDarkBlue.opacity(0.9) : Color.white.opacity(0.95))
                .shadow(color: Color.secondary, radius: 2)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(tint, lineWidth: 2))
        }
    }
}
