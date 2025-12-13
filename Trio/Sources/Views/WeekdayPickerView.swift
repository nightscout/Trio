import SwiftUI

/// A multi-select day of week picker view.
/// Allows users to select one or more days for profile scheduling.
struct WeekdayPickerView: View {
    @Binding var selectedDays: Set<Weekday>

    /// Days that are already assigned to other profiles (shown with warning indicator)
    var conflictingDays: Set<Weekday> = []

    /// Map of conflicting days to profile names that own them
    var conflictingDayOwners: [Weekday: String] = [:]

    /// Whether to show quick select options (Weekdays, Weekends, All)
    var showQuickSelect: Bool = true

    /// State for confirmation alert
    @State private var showConflictAlert = false
    @State private var pendingConflictDay: Weekday?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showQuickSelect {
                quickSelectButtons
            }

            dayButtons

            if !conflictingDays.isEmpty {
                Text("Days with ⚠️ are assigned to other profiles and will be reassigned.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .alert("Reassign Day?", isPresented: $showConflictAlert) {
            Button("Cancel", role: .cancel) {
                pendingConflictDay = nil
            }
            Button("Reassign") {
                if let day = pendingConflictDay {
                    selectedDays.insert(day)
                    pendingConflictDay = nil
                }
            }
        } message: {
            if let day = pendingConflictDay {
                let ownerName = conflictingDayOwners[day] ?? "another profile"
                Text("\(day.localizedName) is currently assigned to \"\(ownerName)\". Selecting it will reassign it to this profile.")
            }
        }
    }

    @ViewBuilder
    private var quickSelectButtons: some View {
        HStack(spacing: 8) {
            QuickSelectButton(
                title: NSLocalizedString("Weekdays", comment: "Quick select weekdays"),
                isSelected: selectedDays == Weekday.weekdays
            ) {
                selectDaysWithConflictCheck(Weekday.weekdays)
            }

            QuickSelectButton(
                title: NSLocalizedString("Weekends", comment: "Quick select weekends"),
                isSelected: selectedDays == Weekday.weekend
            ) {
                selectDaysWithConflictCheck(Weekday.weekend)
            }

            QuickSelectButton(
                title: NSLocalizedString("All", comment: "Quick select all days"),
                isSelected: selectedDays == Weekday.allDays
            ) {
                selectDaysWithConflictCheck(Weekday.allDays)
            }

            QuickSelectButton(
                title: NSLocalizedString("None", comment: "Quick select no days"),
                isSelected: selectedDays.isEmpty
            ) {
                selectedDays = []
            }
        }
    }

    @ViewBuilder
    private var dayButtons: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases) { day in
                DayButton(
                    day: day,
                    isSelected: selectedDays.contains(day),
                    isConflicting: conflictingDays.contains(day) && !selectedDays.contains(day)
                ) {
                    handleDayTap(day)
                }
            }
        }
    }

    private func handleDayTap(_ day: Weekday) {
        if selectedDays.contains(day) {
            // Always allow deselection
            selectedDays.remove(day)
        } else if conflictingDays.contains(day) {
            // Show confirmation for conflicting days
            pendingConflictDay = day
            showConflictAlert = true
        } else {
            // Normal selection
            selectedDays.insert(day)
        }
    }

    private func selectDaysWithConflictCheck(_ days: Set<Weekday>) {
        let conflicts = days.intersection(conflictingDays).subtracting(selectedDays)
        if conflicts.isEmpty {
            selectedDays = days
        } else {
            // For quick select, just select all including conflicts (simpler UX)
            selectedDays = days
        }
    }
}

// MARK: - Supporting Views

private struct QuickSelectButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct DayButton: View {
    let day: Weekday
    let isSelected: Bool
    let isConflicting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Text(day.veryShortName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .bold : .regular)
                    .frame(width: 36, height: 36)
                    .background(backgroundColor)
                    .foregroundColor(foregroundColor)
                    .cornerRadius(18)
                    .overlay(
                        Circle()
                            .stroke(borderColor, lineWidth: isConflicting ? 2 : 0)
                    )

                if isConflicting {
                    Text("⚠️")
                        .font(.system(size: 10))
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var backgroundColor: Color {
        if isConflicting {
            return Color(.systemGray5)
        }
        return isSelected ? Color.accentColor : Color(.secondarySystemBackground)
    }

    private var foregroundColor: Color {
        if isConflicting {
            return .primary
        }
        return isSelected ? .white : .primary
    }

    private var borderColor: Color {
        isConflicting ? .orange : .clear
    }
}

// MARK: - Inline Compact Picker

/// A more compact inline picker for use in forms
struct WeekdayInlinePicker: View {
    @Binding var selectedDays: Set<Weekday>
    var conflictingDays: Set<Weekday> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Days")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                ForEach(Weekday.allCases) { day in
                    CompactDayButton(
                        day: day,
                        isSelected: selectedDays.contains(day),
                        isConflicting: conflictingDays.contains(day)
                    ) {
                        toggleDay(day)
                    }
                }
            }

            if !selectedDays.isEmpty {
                Text(selectedDays.formattedString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func toggleDay(_ day: Weekday) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }
}

private struct CompactDayButton: View {
    let day: Weekday
    let isSelected: Bool
    let isConflicting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(day.veryShortName)
                .font(.caption2)
                .fontWeight(isSelected ? .bold : .regular)
                .frame(width: 28, height: 28)
                .background(backgroundColor)
                .foregroundColor(foregroundColor)
                .cornerRadius(14)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isConflicting)
    }

    private var backgroundColor: Color {
        if isConflicting {
            return Color(.systemGray5)
        }
        return isSelected ? Color.accentColor : Color(.tertiarySystemBackground)
    }

    private var foregroundColor: Color {
        if isConflicting {
            return .secondary
        }
        return isSelected ? .white : .primary
    }
}

// MARK: - Preview

#if DEBUG
    struct WeekdayPickerView_Previews: PreviewProvider {
        static var previews: some View {
            VStack(spacing: 20) {
                WeekdayPickerView(
                    selectedDays: .constant([.monday, .wednesday, .friday]),
                    conflictingDays: [.saturday, .sunday]
                )

                Divider()

                WeekdayInlinePicker(
                    selectedDays: .constant([.monday, .tuesday, .wednesday, .thursday, .friday])
                )
            }
            .padding()
        }
    }
#endif
