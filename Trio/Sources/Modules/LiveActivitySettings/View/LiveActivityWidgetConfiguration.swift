import Charts
import Foundation
import SwiftUI
import Swinject
import UniformTypeIdentifiers

struct LiveActivityWidgetConfiguration: BaseView {
    let resolver: Resolver

    @ObservedObject var state: LiveActivitySettings.StateModel

    @State private var selectedItems: [LiveActivityItem?] = Array(repeating: nil, count: 4)
    @State private var showAddItemDialog: Bool = false
    @State private var buttonIndexToUpdate: Int?
    @State private var itemToRemove: LiveActivityItem?
    @State private var isRemovalConfirmationPresented: Bool = false
    @State private var glucoseData: [DummyGlucoseData] = []

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    @Environment(AppState.self) var appState

    private var color: LinearGradient {
        colorScheme == .dark ? LinearGradient(
            gradient: Gradient(colors: [
                Color.bgDarkBlue,
                Color.bgDarkerDarkBlue
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
            :
            LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                startPoint: .top,
                endPoint: .bottom
            )
    }

    private func generateDummyGlucoseData() -> [DummyGlucoseData] {
        var data = [DummyGlucoseData]()
        let totalMinutes = 6 * 60
        let interval = 5

        var glucoseLevel: Double = 90 // Start at a normal fasting glucose level

        for minute in stride(from: 0, to: totalMinutes, by: interval) {
            let time = Double(minute) / 60.0 // Convert minutes to hours

            let trendFactor: Double
            let randomFactor = Double.random(in: -5 ... 5) // Add slight randomness to each point

            // Simulate different phases during the 6-hour window
            if time < 1 { // Stable glucose (pre-meal or fasting period)
                trendFactor = 0.5 + randomFactor // Small increase with some variability
            } else if time >= 1, time < 2 { // Glucose rising (e.g., post-meal spike)
                trendFactor = 3.0 + randomFactor // Rapid increase with slight variation
            } else if time >= 2, time < 3.5 { // Peak and plateau
                trendFactor = -0.1 + randomFactor // Gradual decrease after the peak with variability
            } else if time >= 3.5, time < 4.5 { // Second peak (optional, simulate another meal)
                trendFactor = 2.5 + randomFactor // Another spike with some randomness
            } else { // Post-meal decrease (insulin effect)
                trendFactor = -1.5 + randomFactor // Glucose decreasing gradually with some variability
            }

            // Calculate the next glucose level with trend factors
            glucoseLevel += trendFactor

            // Ensure glucose level doesn't go out of realistic bounds:
            glucoseLevel = max(70, min(glucoseLevel, 200))

            data.append(DummyGlucoseData(time: Double(minute), glucoseLevel: Int(glucoseLevel.rounded())))
        }
        return data
    }

    var body: some View {
        VStack {
            Group {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(localized: "Live Activity Personalization").uppercased())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundColor(.secondary)
                        .font(.footnote)
                        .padding(.leading)
                }
            }.padding(.bottom, -15)

            GroupBox {
                VStack {
                    dummyChart(glucoseData)

                    HStack(spacing: 15) {
                        ForEach(visibleSlotIndices, id: \.self) { index in
                            widgetButton(for: index)
                        }
                    }
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                            .foregroundColor(.gray)
                    )
                    .cornerRadius(12)
                }

            }.padding(.vertical).groupBoxStyle(.dummyChart)

            Group {
                HStack {
                    Image(systemName: "info.circle")
                    Text(
                        "To re-order widgets, remove them and re-add them in the desired order."
                    )
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(.secondary)
                .font(.footnote)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Widget Configuration")
        .navigationBarTitleDisplayMode(.automatic)
        .onAppear {
            if glucoseData.isEmpty {
                glucoseData = generateDummyGlucoseData()
            }
            loadOrder() // Load the saved order when the view appears
        }
        .glassActionSheet(
            "Add Widget",
            isPresented: $showAddItemDialog,
            actions: addableItems(at: buttonIndexToUpdate).map { item in
                GlassSheetAction(verbatim: item.displayName) {
                    if let index = buttonIndexToUpdate {
                        addItem(item, at: index)
                    }
                }
            }
        )
    }

    @ViewBuilder private func widgetButton(for index: Int) -> some View {
        if index < selectedItems.count, let selectedItem = selectedItems[index] {
            // Display selected item preview
            ZStack(alignment: .topTrailing) {
                getItemPreview(for: selectedItem)
                    .frame(width: previewWidth(for: selectedItem), height: 50)
                    .padding(5)
                    .background(Color.clear)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary, lineWidth: 1)
                    )
                Button(action: {
                    isRemovalConfirmationPresented = true
                    itemToRemove = selectedItem
                }) {
                    Image(systemName: "trash.circle.fill")
                        .foregroundColor(Color(UIColor.systemGray2))
                        .background(Color.white)
                        .clipShape(Circle())
                        .font(.title3)
                }
                .accessibilityLabel(Text("Remove widget"))
                .offset(x: 10, y: -10)
                .glassActionSheet(
                    isPresented: $isRemovalConfirmationPresented,
                    actions: [
                        GlassSheetAction("Remove Widget", role: .destructive) {
                            if let itemToRemove = itemToRemove {
                                removeItem(itemToRemove)
                            }
                        }
                    ]
                )
            }
        } else {
            // Show "+" symbol for empty slots
            Button(action: {
                buttonIndexToUpdate = index
                showAddItemDialog.toggle()
            }) {
                VStack {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                .frame(width: 50, height: 50)
                .padding(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundColor(.primary)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Add widget"))
        }
    }

    private func getItemPreview(for item: LiveActivityItem) -> some View {
        switch item {
        case .currentGlucoseLarge:
            return AnyView(currentGlucoseLargePreview)
        case .currentGlucose:
            return AnyView(currentGlucosePreview)
        case .currentGlucoseWide:
            return AnyView(currentGlucoseWidePreview)
        case .wideContinuation:
            return AnyView(EmptyView())
        case .cob:
            return AnyView(cobPreview)
        case .iob:
            return AnyView(iobPreview)
        case .updatedLabel:
            return AnyView(updatedLabelPreview)
        case .totalDailyDose:
            return AnyView(totalDailyDosePreview)
        }
    }

    @ViewBuilder private func dummyChart(_ glucoseData: [DummyGlucoseData]) -> some View {
        Chart {
            ForEach(glucoseData) { data in
                let pointMarkColor = Trio.getDynamicGlucoseColor(
                    glucoseValue: Decimal(data.glucoseLevel),
                    highGlucoseColorValue: !(state.settingsManager.settings.glucoseColorScheme == .dynamicColor) ? state
                        .settingsManager.settings.high : Decimal(220),
                    lowGlucoseColorValue: !(state.settingsManager.settings.glucoseColorScheme == .dynamicColor) ? state
                        .settingsManager.settings.low : Decimal(55),
                    targetGlucose: Decimal(100),
                    glucoseColorScheme: state.settingsManager.settings.glucoseColorScheme
                )

                PointMark(
                    x: .value("Time", data.time),
                    y: .value("Glucose Level", data.glucoseLevel)
                ).foregroundStyle(pointMarkColor).symbolSize(15)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine(stroke: .init(lineWidth: 0.2, dash: [2, 3])).foregroundStyle(Color.white)
                AxisValueLabel().foregroundStyle(.primary).font(.footnote)
            }
        }
        .chartYScale(domain: 39 ... 200)
        .chartYAxis(.hidden)
        .chartPlotStyle { plotContent in
            plotContent
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.cyan.opacity(0.15))
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .chartXAxis {
            AxisMarks(position: .automatic) { _ in
                AxisGridLine(stroke: .init(lineWidth: 0.2, dash: [2, 3])).foregroundStyle(Color.primary)
            }
        }
        .frame(height: 100)
    }

    private var currentGlucoseLargePreview: some View {
        HStack(alignment: .center) {
            Text("123")
                + Text("\u{2192}")
        }
        .foregroundStyle(Color.loopGreen)
        .fontWeight(.bold)
        .font(.subheadline)
    }

    private var currentGlucoseWidePreview: some View {
        HStack(alignment: .center, spacing: 4) {
            (Text("123") + Text("\u{2192}"))
                .foregroundStyle(Color.loopGreen)
            Text("+6").foregroundStyle(.primary)
        }
        .fontWeight(.bold)
        .font(.subheadline)
    }

    private var currentGlucosePreview: some View {
        VStack {
            HStack(alignment: .center) {
                Text("123")
                    .fontWeight(.bold)
                    .font(.caption)
            }
            HStack(spacing: -5) {
                HStack {
                    Text("\u{2192}")
                    Text("+6")
                }.foregroundStyle(.primary).font(.caption2)
            }
        }
    }

    private var cobPreview: some View {
        VStack(spacing: 2) {
            Text("25 g").fontWeight(.bold).font(.caption)
            Text("COB").font(.caption2).foregroundStyle(.primary)
        }
    }

    private var iobPreview: some View {
        VStack(spacing: 2) {
            Text("2 U").fontWeight(.bold).font(.caption)
            Text("IOB").font(.caption2).foregroundStyle(.primary)
        }
    }

    private var updatedLabelPreview: some View {
        VStack {
            Text("19:05")
                .fontWeight(.bold)
                .font(.caption)
                .foregroundStyle(.primary)

            Text("Updated").font(.caption2).foregroundStyle(.primary)
        }
    }

    private var totalDailyDosePreview: some View {
        VStack {
            Text("43.21 U")
                .fontWeight(.bold)
                .font(.caption)
                .foregroundStyle(.primary)

            Text("TDD").font(.caption2).foregroundStyle(.primary)
        }
    }

    /// Slots that start an item. The second slot of a double-width item is covered by that item's button,
    /// so it is not drawn on its own.
    private var visibleSlotIndices: [Int] {
        selectedItems.indices.filter { selectedItems[$0] != .wideContinuation }
    }

    /// Width of a slot button's content. A double-width item spans two 50pt slots, the 15pt gap between them,
    /// and the 5pt of padding each of those two buttons would have had facing that gap, so the row of slots
    /// keeps its overall width.
    private func previewWidth(for item: LiveActivityItem) -> CGFloat {
        item.slotWidth > 1 ? 50 * 2 + 15 + 10 : 50
    }

    /// Items still available for the tapped slot: not already placed, and wide enough to fit from there on.
    private func addableItems(at index: Int?) -> [LiveActivityItem] {
        LiveActivityItem.selectableItems.filter { !selectedItems.contains($0) && fits($0, at: index) }
    }

    /// Whether `item` can start at `index` without running past the last slot or over an occupied one.
    private func fits(_ item: LiveActivityItem, at index: Int?) -> Bool {
        guard let index, selectedItems.indices.contains(index) else { return false }
        guard item.slotWidth > 1 else { return true }

        let lastSlot = index + item.slotWidth - 1
        guard lastSlot < selectedItems.count else { return false }
        // The slot the user tapped is empty by definition; only the ones a wide item would swallow matter.
        return (index + 1 ... lastSlot).allSatisfy { selectedItems[$0] == nil }
    }

    private func loadOrder() {
        if let savedItems = UserDefaults.standard.loadLiveActivityOrder() {
            var items = Array(savedItems.prefix(4))
            items += Array(repeating: nil, count: 4 - items.count)
            selectedItems = normalized(items)
        } else {
            selectedItems = LiveActivityItem.defaultItems
            saveOrder()
        }
    }

    /// Repairs a saved order so every double-width item is followed by its continuation placeholder, and no
    /// placeholder is left stranded. Guards against orders written by another app version or an interrupted edit.
    private func normalized(_ items: [LiveActivityItem?]) -> [LiveActivityItem?] {
        var result = items
        var index = 0

        while index < result.count {
            let item = result[index]

            if let item, item.slotWidth > 1 {
                let lastSlot = index + item.slotWidth - 1
                if lastSlot < result.count {
                    for slot in (index + 1) ... lastSlot {
                        result[slot] = .wideContinuation
                    }
                    index = lastSlot + 1
                    continue
                }
                // Not enough room left for the item's other slot, so drop it.
                result[index] = nil
            } else if item == .wideContinuation {
                // Not preceded by a double-width item.
                result[index] = nil
            }

            index += 1
        }

        return result
    }

    private func saveOrder() {
        UserDefaults.standard.saveLiveActivityOrder(selectedItems)
        Foundation.NotificationCenter.default.post(name: .liveActivityOrderDidChange, object: nil)
    }

    private func addItem(_ item: LiveActivityItem, at index: Int) {
        guard fits(item, at: index) else { return }

        selectedItems[index] = item
        for slot in stride(from: index + 1, to: index + item.slotWidth, by: 1) {
            selectedItems[slot] = .wideContinuation
        }
        saveOrder()
    }

    private func removeItem(_ item: LiveActivityItem) {
        guard let index = selectedItems.firstIndex(of: item) else { return }

        for slot in stride(from: index, to: index + item.slotWidth, by: 1) where selectedItems.indices.contains(slot) {
            selectedItems[slot] = nil
        }
        saveOrder()
    }
}

// Extension for UserDefaults to save and load the order
extension UserDefaults {
    private enum Keys {
        static let liveActivityOrder = "liveActivityOrder"
    }

    func saveLiveActivityOrder(_ items: [LiveActivityItem?]) {
        let itemStrings = items.map { $0?.rawValue ?? "" }
        set(itemStrings, forKey: Keys.liveActivityOrder)
    }

    func loadLiveActivityOrder() -> [LiveActivityItem?]? {
        if let itemStrings = array(forKey: Keys.liveActivityOrder) as? [String] {
            return itemStrings.map { $0.isEmpty ? nil : LiveActivityItem(rawValue: $0) }
        }
        return nil
    }
}

// Enum to represent each live activity item
enum LiveActivityItem: String, CaseIterable, Identifiable {
    case currentGlucoseLarge
    case currentGlucose
    case currentGlucoseWide
    case iob
    case cob
    case updatedLabel
    case totalDailyDose
    /// Holds the second slot of the preceding double-width item. Never offered in the "Add Widget" sheet.
    case wideContinuation

    var id: String { rawValue }

    static var defaultItems: [LiveActivityItem] {
        [.currentGlucose, .iob, .cob, .updatedLabel]
    }

    /// Items a user can pick, i.e. everything but the internal continuation placeholder.
    static var selectableItems: [LiveActivityItem] {
        allCases.filter { $0 != .wideContinuation }
    }

    /// Number of the four configuration slots this item occupies.
    var slotWidth: Int {
        self == .currentGlucoseWide ? 2 : 1
    }

    var displayName: String {
        switch self {
        case .currentGlucoseLarge:
            return String(
                localized: "Glucose and Trend, no Delta",
                comment: "Live Activity widget icon label for Glucose and Trend, no Delta"
            )
        case .currentGlucose:
            return String(
                localized: "Glucose, Trend, Delta",
                comment: "Live Activity widget icon label for Glucose, Trend, Delta"
            )
        case .currentGlucoseWide:
            return String(
                localized: "Glucose, Trend, Delta (Double Width)",
                comment: "Live Activity widget icon label for the double-width Glucose, Trend, Delta item"
            )
        case .wideContinuation:
            return String(
                localized: "Reserved",
                comment: "Live Activity widget icon label for the slot taken by a double-width item"
            )
        case .iob:
            return String(
                localized: "Insulin on Board (IOB)",
                comment: "Live Activity widget icon label for Insulin on Board (IOB)"
            )
        case .cob:
            return String(localized: "Carbs on Board (COB)", comment: "Live Activity widget icon label for Carbs on Board (COB)")
        case .updatedLabel:
            return String(localized: "Last Updated", comment: "Live Activity widget icon label for Last Updated")
        case .totalDailyDose:
            return String(localized: "Total Daily Dose", comment: "Live Activity widget icon label for Total Daily Dose")
        }
    }
}

struct DummyGlucoseData: Identifiable {
    let id = UUID()
    let time: Double // Time in hours
    let glucoseLevel: Int // Glucose level in mg/dL
}

struct DummyChartGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack {
            configuration.content
        }
        .padding()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(Color.chart, in: RoundedRectangle(cornerRadius: 12))
        .frame(width: UIScreen.main.bounds.width * 0.9)
    }
}

extension GroupBoxStyle where Self == DummyChartGroupBoxStyle {
    static var dummyChart: DummyChartGroupBoxStyle { .init() }
}
