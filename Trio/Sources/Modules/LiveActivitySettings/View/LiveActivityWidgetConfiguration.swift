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
                        ForEach(0 ..< 4, id: \.self) { index in
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
        .confirmationDialog("Add Widget", isPresented: $showAddItemDialog, titleVisibility: .visible) {
            ForEach(LiveActivityItem.allCases.filter { !selectedItems.contains($0) }, id: \.self) { item in
                Button(item.displayName) {
                    if let index = buttonIndexToUpdate {
                        addItem(item, at: index)
                    }
                }
            }
        }
    }

    @ViewBuilder private func widgetButton(for index: Int) -> some View {
        if index < selectedItems.count, let selectedItem = selectedItems[index] {
            // Display selected item preview
            ZStack(alignment: .topTrailing) {
                getItemPreview(for: selectedItem)
                    .frame(width: 50, height: 50)
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
                .offset(x: 10, y: -10)
                .confirmationDialog("Remove Widget", isPresented: $isRemovalConfirmationPresented, titleVisibility: .hidden) {
                    Button("Remove Widget", role: .destructive) {
                        if let itemToRemove = itemToRemove {
                            removeItem(itemToRemove)
                        }
                    }
                }
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
        }
    }

    private func getItemPreview(for item: LiveActivityItem) -> some View {
        switch item {
        case .currentGlucoseLarge:
            return AnyView(currentGlucoseLargePreview)
        case .currentGlucose:
            return AnyView(currentGlucosePreview)
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
                        .settingsManager.settings.highGlucose : Decimal(220),
                    lowGlucoseColorValue: !(state.settingsManager.settings.glucoseColorScheme == .dynamicColor) ? state
                        .settingsManager.settings.lowGlucose : Decimal(55),
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

    private func loadOrder() {
        if let savedItems = UserDefaults.standard.loadLiveActivityOrder() {
            selectedItems = savedItems.count == 4 ? savedItems : savedItems + Array(repeating: nil, count: 4 - savedItems.count)
        } else {
            selectedItems = LiveActivityItem.defaultItems
            saveOrder()
        }
    }

    private func saveOrder() {
        UserDefaults.standard.saveLiveActivityOrder(selectedItems)
        Foundation.NotificationCenter.default.post(name: .liveActivityOrderDidChange, object: nil)
    }

    private func addItem(_ item: LiveActivityItem, at index: Int) {
        selectedItems[index] = item
        saveOrder()
    }

    private func removeItem(_ item: LiveActivityItem) {
        if let index = selectedItems.firstIndex(of: item) {
            selectedItems[index] = nil
            saveOrder()
        }
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
    case iob
    case cob
    case updatedLabel
    case totalDailyDose

    var id: String { rawValue }

    static var defaultItems: [LiveActivityItem] {
        [.currentGlucose, .iob, .cob, .updatedLabel]
    }

    var displayName: String {
        switch self {
        case .currentGlucoseLarge:
            return "Glucose and Trend, no Delta"
        case .currentGlucose:
            return "Glucose, Trend, Delta"
        case .iob:
            return "Insulin on Board (IOB)"
        case .cob:
            return "Carbs on Board (IOB)"
        case .updatedLabel:
            return "Last Updated"
        case .totalDailyDose:
            return "Total Daily Dose"
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
