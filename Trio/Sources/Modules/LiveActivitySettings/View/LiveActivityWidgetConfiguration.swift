import Charts
import CoreTransferable
import Foundation
import SwiftUI
import Swinject
import UniformTypeIdentifiers

struct LiveActivityWidgetConfiguration: BaseView {
    let resolver: Resolver

    @ObservedObject var state: LiveActivitySettings.StateModel

    @State private var placedItems: [LiveActivityItem] = []
    @State private var glucoseData: [DummyGlucoseData] = []
    @State private var targetedSlot: Int?
    @State private var isPaletteTargeted: Bool = false

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    private static let slotCount = 4
    private static let slotSize: CGFloat = 50
    private static let slotSpacing: CGFloat = 15
    private static let slotPadding: CGFloat = 5

    private var usedSlots: Int {
        placedItems.reduce(0) { $0 + $1.slotWidth }
    }

    private var freeSlots: Int {
        max(0, Self.slotCount - usedSlots)
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
        ScrollView {
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
                        layoutRow
                    }
                }.padding(.vertical).groupBoxStyle(.dummyChart)

                Group {
                    HStack(alignment: .top) {
                        Image(systemName: "info.circle")
                        Text(
                            "Drag a widget to move it. Drag one up from Available Widgets to add it, or drop it back onto the list to remove it."
                        )
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(.secondary)
                    .font(.footnote)
                    .padding(.horizontal)

                paletteSection.padding(.top)
            }
            .padding()
        }
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
    }

    // MARK: - Layout row

    private var layoutRow: some View {
        HStack(spacing: Self.slotSpacing) {
            ForEach(placedItems, id: \.self) { item in
                placedSlot(item)
            }

            ForEach(0 ..< freeSlots, id: \.self) { offset in
                emptySlot(position: placedItems.count + offset)
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

    private func placedSlot(_ item: LiveActivityItem) -> some View {
        let index = placedItems.firstIndex(of: item) ?? placedItems.count
        let isDropTarget = targetedSlot == index

        return ZStack(alignment: .topTrailing) {
            widgetTile(item, highlighted: isDropTarget)

            Button(action: { remove(item) }) {
                Image(systemName: "trash.circle.fill")
                    .foregroundColor(Color(UIColor.systemGray2))
                    .background(Color.white)
                    .clipShape(Circle())
                    .font(.title3)
            }
            .accessibilityLabel(Text("Remove \(item.displayName)"))
            .offset(x: 10, y: -10)
        }
        .draggable(item) { widgetTile(item) }
        .dropDestination(for: LiveActivityItem.self) { dropped, _ in
            targetedSlot = nil
            guard let dropped = dropped.first else { return false }
            return place(dropped, at: index)
        } isTargeted: { hovering in
            targetedSlot = hovering ? index : nil
        }
        .accessibilityLabel(Text(item.displayName))
        .accessibilityValue(Text("Position \(index + 1) of \(placedItems.count)"))
    }

    private func emptySlot(position: Int) -> some View {
        let isDropTarget = targetedSlot == position

        return Image(systemName: "plus")
            .font(.title2)
            .foregroundColor(.secondary)
            .frame(width: Self.slotSize, height: Self.slotSize)
            .padding(Self.slotPadding)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        style: StrokeStyle(lineWidth: isDropTarget ? 2 : 1, dash: isDropTarget ? [] : [5])
                    )
                    .foregroundColor(isDropTarget ? Color.accentColor : Color.primary)
            )
            .dropDestination(for: LiveActivityItem.self) { dropped, _ in
                targetedSlot = nil
                guard let dropped = dropped.first else { return false }
                return place(dropped, at: placedItems.count)
            } isTargeted: { hovering in
                targetedSlot = hovering ? position : nil
            }
            .accessibilityLabel(Text("Empty widget slot"))
    }

    private func widgetTile(_ item: LiveActivityItem, highlighted: Bool = false) -> some View {
        getItemPreview(for: item)
            .frame(width: previewWidth(for: item), height: Self.slotSize)
            .padding(Self.slotPadding)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.chart))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(highlighted ? Color.accentColor : Color.primary, lineWidth: highlighted ? 2 : 1)
            )
    }

    private func previewWidth(for item: LiveActivityItem) -> CGFloat {
        item.slotWidth > 1
            ? Self.slotSize * 2 + Self.slotSpacing + Self.slotPadding * 2
            : Self.slotSize
    }

    // MARK: - Palette

    private static let paletteRest: [LiveActivityItem] = [
        .currentGlucoseLarge, .currentGlucoseLargeUncolored, .iob, .cob, .updatedLabel, .totalDailyDose,
    ]

    private static var paletteRestRows: [[LiveActivityItem]] {
        stride(from: 0, to: paletteRest.count, by: 3).map {
            Array(paletteRest[$0 ..< min($0 + 3, paletteRest.count)])
        }
    }

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Available Widgets").uppercased())
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(.secondary)
                .font(.footnote)

            Grid(alignment: .top, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    paletteCell(.currentGlucoseWideUncolored).gridCellColumns(2)
                    paletteCell(.currentGlucose)
                }
                GridRow {
                    paletteCell(.currentGlucoseWide).gridCellColumns(2)
                    paletteCell(.currentGlucoseColored)
                }
                ForEach(Self.paletteRestRows, id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { item in
                            paletteCell(item)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(isPaletteTargeted ? 0.25 : 0.1))
        )
        .dropDestination(for: LiveActivityItem.self) { dropped, _ in
            isPaletteTargeted = false
            guard let dropped = dropped.first else { return false }
            return remove(dropped)
        } isTargeted: { isPaletteTargeted = $0 }
    }

    @ViewBuilder private func paletteCell(_ item: LiveActivityItem) -> some View {
        let isPlaced = placedItems.contains(item)
        let canPlace = !isPlaced && freeSlots >= item.slotWidth
        let unavailableReason: LocalizedStringKey = isPlaced ? "Already in the layout" : "Not enough room"

        let cell = VStack(spacing: 6) {
            widgetTile(item)

            Text(item.displayName)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .opacity(canPlace ? 1 : 0.4)

        if canPlace {
            cell
                .contentShape(Rectangle())
                .onTapGesture { place(item, at: placedItems.count) }
                .draggable(item) { widgetTile(item) }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(Text(item.displayName))
                .accessibilityHint(Text("Adds this widget to the layout"))
        } else {
            cell
                .accessibilityLabel(Text(item.displayName))
                .accessibilityValue(Text(unavailableReason))
        }
    }

    // MARK: - Previews

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

    private func getItemPreview(for item: LiveActivityItem) -> some View {
        switch item {
        case .currentGlucoseLarge:
            return AnyView(currentGlucoseLargePreview(colored: true))
        case .currentGlucoseLargeUncolored:
            return AnyView(currentGlucoseLargePreview(colored: false))
        case .currentGlucose:
            return AnyView(currentGlucosePreview(colored: false))
        case .currentGlucoseColored:
            return AnyView(currentGlucosePreview(colored: true))
        case .currentGlucoseWide:
            return AnyView(currentGlucoseWidePreview(colored: true))
        case .currentGlucoseWideUncolored:
            return AnyView(currentGlucoseWidePreview(colored: false))
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

    private func currentGlucoseLargePreview(colored: Bool) -> some View {
        HStack(alignment: .center) {
            Text("123")
                + Text("\u{2192}")
        }
        .foregroundStyle(colored ? Color.loopGreen : Color.primary)
        .fontWeight(.bold)
        .font(.subheadline)
    }

    private func currentGlucoseWidePreview(colored: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            (Text("123") + Text("\u{2192}"))
                .font(.largeTitle)
                .foregroundStyle(colored ? Color.loopGreen : Color.primary)
            Text("+6")
                .font(.largeTitle)
                .foregroundStyle(.primary)
        }
        .fontWeight(.bold)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func currentGlucosePreview(colored: Bool) -> some View {
        VStack {
            HStack(alignment: .center) {
                Text("123")
                    .fontWeight(.bold)
                    .font(.caption)
                    .foregroundStyle(colored ? Color.loopGreen : Color.primary)
            }
            HStack(spacing: -5) {
                HStack {
                    Text("\u{2192}")
                    Text("+6")
                }.foregroundStyle(colored ? Color.loopGreen : Color.primary).font(.caption2)
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

    // MARK: - Layout changes

    @discardableResult private func place(_ item: LiveActivityItem, at index: Int) -> Bool {
        guard item != .wideContinuation else { return false }

        var items = placedItems

        if let currentIndex = items.firstIndex(of: item) {
            guard currentIndex != index else { return false }
            items.remove(at: currentIndex)
        } else {
            guard freeSlots >= item.slotWidth else { return false }
        }

        items.insert(item, at: min(index, items.count))
        apply(items)
        return true
    }

    @discardableResult private func remove(_ item: LiveActivityItem) -> Bool {
        guard let index = placedItems.firstIndex(of: item) else { return false }

        var items = placedItems
        items.remove(at: index)
        apply(items)
        return true
    }

    private func apply(_ items: [LiveActivityItem]) {
        withAnimation(.easeInOut(duration: 0.2)) {
            placedItems = items
        }
        saveOrder(items)
    }

    // MARK: - Persistence

    private func loadOrder() {
        guard let savedItems = UserDefaults.standard.loadLiveActivityOrder() else {
            let defaults = LiveActivityItem.defaultItems
            placedItems = defaults
            saveOrder(defaults)
            return
        }

        placedItems = layoutItems(from: savedItems)
    }

    private func saveOrder(_ items: [LiveActivityItem]) {
        UserDefaults.standard.saveLiveActivityOrder(slotArray(from: items))
        Foundation.NotificationCenter.default.post(name: .liveActivityOrderDidChange, object: nil)
    }

    private func slotArray(from items: [LiveActivityItem]) -> [LiveActivityItem?] {
        var slots: [LiveActivityItem?] = []

        for item in items {
            slots.append(item)

            let continuations: [LiveActivityItem?] = Array(
                repeating: .wideContinuation,
                count: item.slotWidth - 1
            )
            slots.append(contentsOf: continuations)
        }

        let padding: [LiveActivityItem?] = Array(repeating: nil, count: max(0, Self.slotCount - slots.count))
        slots.append(contentsOf: padding)

        return Array(slots.prefix(Self.slotCount))
    }

    private func layoutItems(from slots: [LiveActivityItem?]) -> [LiveActivityItem] {
        var items: [LiveActivityItem] = []
        var used = 0

        for slot in slots.prefix(Self.slotCount) {
            guard let slot, slot != .wideContinuation, !items.contains(slot) else { continue }
            guard used + slot.slotWidth <= Self.slotCount else { continue }

            items.append(slot)
            used += slot.slotWidth
        }

        return items
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
enum LiveActivityItem: String, CaseIterable, Identifiable, Codable, Transferable {
    case currentGlucoseLarge
    case currentGlucoseLargeUncolored
    case currentGlucose
    case currentGlucoseColored
    case currentGlucoseWide
    case currentGlucoseWideUncolored
    case iob
    case cob
    case updatedLabel
    case totalDailyDose
    case wideContinuation

    var id: String { rawValue }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }

    static var defaultItems: [LiveActivityItem] {
        [.currentGlucose, .iob, .cob, .updatedLabel]
    }

    static var selectableItems: [LiveActivityItem] {
        allCases.filter { $0 != .wideContinuation }
    }

    var slotWidth: Int {
        (self == .currentGlucoseWide || self == .currentGlucoseWideUncolored) ? 2 : 1
    }

    var displayName: String {
        switch self {
        case .currentGlucoseLarge:
            return String(
                localized: "Glucose and Trend (Colored)",
                comment: "Live Activity widget icon label for Glucose and Trend in the glucose color"
            )
        case .currentGlucoseLargeUncolored:
            return String(
                localized: "Glucose and Trend",
                comment: "Live Activity widget icon label for Glucose and Trend in the default text color"
            )
        case .currentGlucose:
            return String(
                localized: "Glucose, Trend, Delta",
                comment: "Live Activity widget icon label for Glucose, Trend, Delta"
            )
        case .currentGlucoseColored:
            return String(
                localized: "Glucose, Trend, Delta (Colored)",
                comment: "Live Activity widget icon label for Glucose, Trend, Delta in the glucose color"
            )
        case .currentGlucoseWide:
            return String(
                localized: "Glucose, Trend, Delta (Double Width, Colored)",
                comment: "Live Activity widget icon label for the double-width Glucose, Trend, Delta item in the glucose color"
            )
        case .currentGlucoseWideUncolored:
            return String(
                localized: "Glucose, Trend, Delta (Double Width)",
                comment: "Live Activity widget icon label for the double-width Glucose, Trend, Delta item in the default text color"
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
