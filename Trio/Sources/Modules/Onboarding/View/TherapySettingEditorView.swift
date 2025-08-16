import SwiftUI

struct TherapySettingEditorView: View {
    @Binding var items: [TherapySettingItem]
    var unit: TherapySettingUnit
    var timeOptions: [TimeInterval]
    var valueOptions: [Decimal]
    var validateOnDelete: (() -> Void)?

    @State private var selectedItemID: UUID?

    var body: some View {
        List {
            HStack {
                Text("Entries").bold()
                Spacer()
                Button {
                    // Prepare and add new entry
                    let lastTime = items.last?.time ?? 0
                    let newTime = min(lastTime + 1800, 23 * 3600 + 1800)
                    let newValue = items.last?.value ?? 1.0
                    items.append(TherapySettingItem(time: newTime, value: newValue))

                    // Reset selected item to close picker
                    selectedItemID = nil

                    // Sort items, in case user has changed time of one item, then taps 'Add'
                    sortTherapyItems()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add")
                    }.foregroundColor(.accentColor)
                }
                .disabled(items.count >= 48)
            }
            .listRowBackground(Color.chart.opacity(0.65))
            .padding(.vertical, 5)

            ForEach($items) { $item in
                VStack(spacing: 0) {
                    Button {
                        selectedItemID = selectedItemID == item.id ? nil : item.id
                        sortTherapyItems()
                    } label: {
                        HStack {
                            HStack {
                                Text(displayText(for: unit, decimalValue: item.value))
                                    .foregroundStyle(
                                        selectedItemID == item.id ? Color.accentColor : Color
                                            .primary
                                    )
                                Text(unit.displayName)
                                    .foregroundStyle(Color.secondary)
                            }

                            Spacer()

                            HStack {
                                Text("starts at").foregroundStyle(Color.secondary)
                                let timeIndex = timeOptions.firstIndex { abs($0 - item.time) < 1 } ?? 0
                                let time = timeOptions[timeIndex]
                                let date = Date(timeIntervalSince1970: time)
                                let timeString = timeFormatter.string(from: date)
                                Text(timeString).foregroundStyle(selectedItemID == item.id ? Color.accentColor : Color.primary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if selectedItemID == item.id {
                        timeValuePickerRow(
                            item: $item,
                            timeOptions: timeOptions,
                            valueOptions: valueOptions,
                            unit: unit
                        )
                        .transition(.slide)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if let index = items.firstIndex(where: { $0.id == item.id }), items.count > 1 {
                        Button(role: .destructive) {
                            items.remove(at: index)
                            selectedItemID = nil
                            validateTherapySettingItems()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listRowBackground(Color.chart.opacity(0.65))

            Rectangle().fill(Color.chart.opacity(0.65)).frame(height: 10)
                .clipShape(
                    .rect(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 10,
                        bottomTrailingRadius: 10,
                        topTrailingRadius: 0
                    )
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: -22, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        // 55 for header row, item counts x 45 for every entry row + 230 for a visible picker row
        .frame(height: 55 + CGFloat(items.count) * 45 + (items.contains(where: { $0.id == selectedItemID }) ? 230 : 0))
        .onAppear {
            // ensure picker is closed when view appears
            selectedItemID = nil
            // sorts items
            validateTherapySettingItems()
        }
        .onDisappear {
            // ensure picker is closed when view appears
            selectedItemID = nil
            // sorts items
            validateTherapySettingItems()
        }
        .onChange(of: items, { _, _ in
            validateTherapySettingItems()
        })
    }

    @ViewBuilder private func timeValuePickerRow(
        item: Binding<TherapySettingItem>,
        timeOptions: [TimeInterval],
        valueOptions: [Decimal],
        unit: TherapySettingUnit
    ) -> some View {
        // Compute unavailable times (already taken by other entries)
        let takenTimes = Set(items.filter { $0.id != item.wrappedValue.id }.map(\.time))
        // Allow current selection even if it’s in the set of taken times.
        let availableTimes = timeOptions.filter { $0 == item.wrappedValue.time || !takenTimes.contains($0) }
        // Determine if this is first item in list (which is locked to 00:00)
        var isFirstItem: Bool {
            items.first == item.wrappedValue
        }

        VStack(spacing: 8) {
            HStack {
                Picker("Value", selection: Binding(
                    get: { Double(item.wrappedValue.value) },
                    set: {
                        item.wrappedValue.value = Decimal($0)
                    }
                )) {
                    ForEach(valueOptions, id: \.self) { value in
                        Text("\(displayText(for: unit, decimalValue: value)) \(unit.displayName)").tag(Double(value))
                    }
                }
                .frame(maxWidth: .infinity)
                .clipped()

                Picker("Time", selection: Binding(
                    get: { item.wrappedValue.time },
                    set: { newTime in
                        // Only update if new time is either not taken, or it is the current value
                        if newTime == item.wrappedValue.time || !takenTimes.contains(newTime) {
                            item.wrappedValue.time = newTime
                            validateTherapySettingItems()
                        }
                    }
                )) {
                    ForEach(availableTimes, id: \.self) { time in
                        Text(timeFormatter.string(from: Date(timeIntervalSince1970: time)))
                            .tag(time)
                            .foregroundStyle(item.wrappedValue.time != 0 ? Color.primary : Color.secondary)
                    }
                }
                // Lock time picker if first item and make it slightly opague
                .opacity(isFirstItem ? 0.5 : 1)
                .disabled(isFirstItem)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .pickerStyle(.wheel)
        }
        .padding(.vertical, 8)
    }

    private func sortTherapyItems() {
        Task { @MainActor in
            withAnimation {
                items = items.sorted { $0.time < $1.time }
            }
        }
    }

    private func validateTherapySettingItems() {
        // validates therapy items (i.e. parsed therapy settings into wrapper class)
        var newItems = Array(Set(items)).sorted { $0.time < $1.time }
        if !newItems.isEmpty {
            var first = newItems[0]
            if first.time != 0 {
                first.time = 0
            }
            newItems[0] = first
        }

        // force ALL items to have new UUIDs (to enforce binding update)
        items = newItems.map { TherapySettingItem(copying: $0, newID: true) }

        // validates underlying "raw" therapy setting (i.e. item of type basal, target, isf, carb ratio)
        validateOnDelete?()
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.timeStyle = .short
        return formatter
    }

    private func displayText(for unit: TherapySettingUnit, decimalValue: Decimal) -> String {
        switch unit {
        case .mmolL,
             .mmolLPerUnit:
            return decimalValue.formattedAsMmolL
        case .gramPerUnit,
             .mgdL,
             .mgdLPerUnit,
             .unitPerHour:
            return decimalValue.description
        }
    }
}

struct TherapySettingItem: Identifiable, Equatable, Hashable {
    var id = UUID()
    var time: TimeInterval = 0 // seconds since start of day
    var value: Decimal = 0

    init(time: TimeInterval, value: Decimal) {
        self.time = time
        self.value = value
    }

    static func == (lhs: TherapySettingItem, rhs: TherapySettingItem) -> Bool {
        lhs.time == rhs.time && lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(time)
        hasher.combine(value)
    }
}

/// Convenience extension to ease copying of existing `TherapySettingItem`s
extension TherapySettingItem {
    init(copying item: TherapySettingItem, newID: Bool = false) {
        id = newID ? UUID() : item.id
        time = item.time
        value = item.value
    }
}

enum TherapySettingUnit: String, CaseIterable {
    case mmolLPerUnit
    case mgdLPerUnit
    case unitPerHour
    case gramPerUnit
    case mmolL
    case mgdL

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mmolLPerUnit:
            return String(localized: "mmol/L/U")
        case .mgdLPerUnit:
            return String(localized: "mg/dL/U")
        case .unitPerHour:
            return String(localized: "U/hr")
        case .gramPerUnit:
            return String(localized: "g/U")
        case .mmolL:
            return "mmol/L"
        case .mgdL:
            return "mg/dL"
        }
    }
}

#Preview {
    @Previewable @State var previewItems = [
        TherapySettingItem(time: 0, value: 1.0),
        TherapySettingItem(time: 1800, value: 1.2)
    ]

    TherapySettingEditorView(
        items: $previewItems,
        unit: .unitPerHour,
        timeOptions: stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 },
        valueOptions: stride(from: 0.0, through: 10.0, by: 0.05).map { Decimal(round(100 * $0) / 100) }
    )
}
