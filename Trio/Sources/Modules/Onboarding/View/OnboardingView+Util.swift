import SwiftUI

struct TherapySettingItem: Identifiable, Equatable {
    var id = UUID()
    var time: TimeInterval // seconds since start of day
    var value: Double
}

struct TimeValuePickerRow: View {
    @Binding var item: TherapySettingItem
    var valueOptions: [Decimal]
    var unit: String

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Time", selection: Binding(
                    get: { item.time },
                    set: { item.time = $0 }
                )) {
                    ForEach(0 ..< 48) { i in
                        let seconds = Double(i * 30 * 60)
                        Text(timeFormatter.string(from: Date(timeIntervalSinceReferenceDate: seconds)))
                            .tag(seconds)
                    }
                }
                .frame(maxWidth: .infinity)
                .clipped()

                Picker("Value", selection: Binding(
                    get: { item.value },
                    set: { item.value = $0 }
                )) {
                    ForEach(valueOptions, id: \.self) { value in
                        Text("\(Double(value), specifier: "%.1f") \(unit)").tag(Double(value))
                    }
                }
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .pickerStyle(.wheel)
        }
        .padding(.vertical, 8)
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter
    }
}

struct TimeValueEditorView: View {
    @Binding var items: [TherapySettingItem]
    var unit: String
    var valueOptions: [Decimal]

    @State private var selectedItemID: UUID?

    var body: some View {
        List {
            HStack {
                Text("Entries").bold()
                Spacer()
                Button {
                    let lastTime = items.last?.time ?? 0
                    let newTime = min(lastTime + 1800, 23 * 3600 + 1800)
                    let newValue = items.last?.value ?? 1.0
                    items.append(TherapySettingItem(time: newTime, value: newValue))
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add")
                    }.foregroundColor(.accentColor)
                }
                .disabled(items.count >= 48)
            }
            .listRowBackground(Color.chart.opacity(0.45))
            .padding(.vertical, 5)

            ForEach($items) { $item in
                VStack(spacing: 0) {
                    Button {
                        selectedItemID = selectedItemID == item.id ? nil : item.id
                    } label: {
                        HStack {
                            HStack {
                                Text("\(item.value, specifier: "%.1f")")
                                    .foregroundStyle(selectedItemID == item.id ? Color.accentColor : Color.primary)
                                Text(unit.description)
                                    .foregroundStyle(Color.secondary)
                            }

                            Spacer()

                            HStack {
                                Text("starts at").foregroundStyle(Color.secondary)

                                let startDate = Date(timeIntervalSinceReferenceDate: item.time)
                                Text(timeFormatter.string(from: startDate))
                                    .foregroundStyle(selectedItemID == item.id ? Color.accentColor : Color.primary)
                            }
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if selectedItemID == item.id {
                        TimeValuePickerRow(
                            item: $item,
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
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listRowBackground(Color.chart.opacity(0.45))

            Rectangle().fill(Color.chart.opacity(0.45)).frame(height: 10)
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
        .scrollContentBackground(.hidden)
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }
}

#Preview {
    @Previewable @State var previewItems = [
        TherapySettingItem(time: 0, value: 1.0),
        TherapySettingItem(time: 1800, value: 1.2)
    ]

    TimeValueEditorView(
        items: $previewItems,
        unit: "U/h",
        valueOptions: stride(from: 0.0, through: 10.0, by: 0.05).map { Decimal(round(100 * $0) / 100) }
    )
}
