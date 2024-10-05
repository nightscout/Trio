import Charts
import Foundation
import SwiftUI
import Swinject
import UniformTypeIdentifiers

struct LiveActivityWidgetConfiguration: BaseView {
    let resolver: Resolver

    @ObservedObject var state: LiveActivitySettings.StateModel

    @State private var selectedItems: [LiveActivityItem] = []
    @State private var showAddItemDialog: Bool = false
    @State private var buttonIndexToUpdate: Int?

    @State private var isEditMode: Bool = false
    @State private var draggingItem: LiveActivityItem?
    @State private var showDeleteAlert: Bool = false

    @Environment(\.colorScheme) var colorScheme

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

    // Dummy data for glucose levels
    private var glucoseData: [DummyChart] {
        var data = [DummyChart]()
        let totalMinutes = 6 * 60 // 6 hours in minutes
        let interval = 5 // 5 minutes interval for each data point

        for minute in stride(from: 0, to: totalMinutes, by: interval) {
            let time = Double(minute) / 60.0 // Convert minutes to hours
            let glucoseLevel = 100 + 20 * sin(time) // Oscillating sine wave pattern
            data.append(DummyChart(time: Double(minute), glucoseLevel: glucoseLevel))
        }
        return data
    }

//    var body: some View {
//            VStack {
//                Group {
//                    VStack(alignment: .leading, spacing: 0) {
//                        Text("Live Activity Personalization".uppercased())
//                            .frame(maxWidth: .infinity, alignment: .leading)
//                            .foregroundColor(.secondary)
//                            .font(.footnote)
//                            .padding(.leading)
//                    }
//                    VStack {
//                        Text(
//                            "Trio offers you to customize your Live Activity lock screen widget. The default configuration will display current glucose, IOB, COB and the time of last algorithm run."
//                        )
//                        .padding()
//                        .font(.footnote)
//                        .foregroundColor(.secondary)
//                    }
//                    .background(
//                        RoundedRectangle(cornerRadius: 10, style: .continuous)
//                            .fill(Color.chart)
//                    )
//                }
//
//                GroupBox {
//                    VStack {
//                        dummyChart
//
//                        HStack {
//                            if selectedItems.isEmpty {
//                                Spacer()
//                                Button(action: {
//                                    showAddItemDialog.toggle()
//                                }) {
//                                    VStack {
//                                        Image(systemName: "plus")
//                                            .font(.title2)
//                                            .foregroundColor(.gray)
//                                    }
//                                    .frame(width: 60, height: 40)
//                                    .overlay(
//                                        RoundedRectangle(cornerRadius: 12)
//                                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
//                                            .foregroundColor(.gray)
//                                    )
//                                }
//                                Spacer()
//                            } else {
//                                ForEach(Array(selectedItems.enumerated()), id: \.element) { index, item in
//                                    if index > 0 {
//                                        Divider()
//                                            .frame(height: 50)
//                                    }
//
//                                    ZStack(alignment: .topTrailing) {
//                                        getItemPreview(for: item)
//                                            .frame(width: 50, height: 50)
//                                            .padding(5)
//                                            .background(
//                                                draggingItem == item ? Color.blue.opacity(0.2) : Color.clear
//                                            )
//                                            .cornerRadius(12)
//                                            .overlay(
//                                                RoundedRectangle(cornerRadius: 12)
//                                                    .stroke(
//                                                        draggingItem == item ? Color.blue : Color.primary,
//                                                        lineWidth: draggingItem == item ? 2 : 1
//                                                    )
//                                            )
//                                            .opacity(draggingItem == item ? 0.85 : 1.0)
//                                            .onDrag {
//                                                self.draggingItem = item
//                                                return NSItemProvider(object: item.rawValue as NSString)
//                                            }
//                                            .onDrop(
//                                                of: [UTType.text],
//                                                delegate: DropViewDelegate(
//                                                    item: item,
//                                                    items: $selectedItems,
//                                                    draggingItem: $draggingItem
//                                                )
//                                            )
//                                            .disabled(!isEditMode)
//                                            .rotationEffect(.degrees(isEditMode ? 2.5 : 0))
//                                            .rotation3DEffect(.degrees(isEditMode ? 2.5 : 0), axis: (x: 0, y: -5, z: 0))
//                                            .animation(
//                                                isEditMode ? Animation.easeInOut(duration: 0.15)
//                                                    .repeatForever(autoreverses: true) : .default,
//                                                value: isEditMode
//                                            )
//                                        if isEditMode {
//                                            Button(action: {
//                                                showDeleteAlert = true
//                                            }) {
//                                                Image(systemName: "minus.circle.fill")
//                                                    .foregroundColor(Color(UIColor.systemGray2)) // Opaque foreground color
//                                                    .background(Color.white) // Adding a background for contrast
//                                                    .clipShape(Circle()) // Make sure the background stays circular
//                                                    .font(.system(size: 20))
//                                            }
//                                            .offset(x: -45, y: -10)
//                                            .alert(isPresented: $showDeleteAlert) {
//                                                Alert(
//                                                    title: Text("Delete Widget"),
//                                                    message: Text("Are you sure you want to delete this widget?"),
//                                                    primaryButton: .destructive(Text("Delete")) {
//                                                        removeItem(item)
//                                                    },
//                                                    secondaryButton: .cancel()
//                                                )
//                                            }
//                                        }
//                                    }
//                                    .animation(.easeInOut, value: draggingItem)
//                                    .frame(maxWidth: .infinity)
//                                }
//                            }
//                        }
//                        .padding()
//                        .overlay(
//                            RoundedRectangle(cornerRadius: 12)
//                                .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
//                                .foregroundColor(.gray)
//                        )
//                        .cornerRadius(12)
//                    }
//                }.padding(.vertical).groupBoxStyle(.dummyChart)
//
//                if isEditMode {
//                    HStack {
//                        Image(systemName: "hand.draw.fill")
//                        Text("Tap 'Add +' to add a widget. Press, drag and drop a widget to re-order a widget.")
//                    }.frame(maxWidth: .infinity, alignment: .leading)
//                        .foregroundColor(.secondary)
//                        .font(.footnote)
//                        .padding(.horizontal)
//                }
//
//                Spacer()
//            }
//            .padding()
//            .scrollContentBackground(.hidden).background(color)
//            .navigationTitle("Widget Configuration")
//            .navigationBarTitleDisplayMode(.automatic)
//            .toolbar {
//                ToolbarItem(placement: .topBarTrailing) {
//                    Button {
//                        isEditMode.toggle()
//                    } label: {
//                        HStack {
//                            Text("Edit")
//                        }
//                    }
//                }
//                ToolbarItem(placement: .topBarTrailing) {
//                    Button {
//                        showAddItemDialog.toggle()
//                    } label: {
//                        HStack {
//                            Text("Add")
//                            Image(systemName: "plus")
//                        }
//                    }
//                }
//            }
//            .confirmationDialog("Add Widget", isPresented: $showAddItemDialog, titleVisibility: .visible) {
//                ForEach(LiveActivityItem.allCases, id: \.self) { item in
//                    Button(item.displayName) {
//                        addItem(item)
//                    }.disabled(selectedItems.contains(item))
//                }
//            }
//            .onAppear {
//                configureView()
//                loadOrder()
//            }
//        }

    var body: some View {
        VStack {
            dummyChart

            HStack {
                ForEach(0 ..< 4) { index in
                    widgetButton(for: index)
                }
            }
            .padding()
        }
        .padding()
        .scrollContentBackground(.hidden).background(color)
        .navigationTitle("Widget Configuration")
        .navigationBarTitleDisplayMode(.automatic)
        .onAppear {
            loadOrder() // Load the saved order when the view appears
        }
        .confirmationDialog("Add Widget", isPresented: $showAddItemDialog, titleVisibility: .visible) {
            ForEach(LiveActivityItem.allCases, id: \.self) { item in
                Button(item.displayName) {
                    if let index = buttonIndexToUpdate {
                        selectedItems[index] = item // Update button index to selected item
                        saveOrder() // Save the order to UserDefaults
                    }
                }
                .disabled(selectedItems.contains(item))
                // This causes the type check error

//                .disabled(selectedItems.contains { $0.value == item }) // Disable already selected items
            }
        }
    }

    @ViewBuilder private func widgetButton(for index: Int) -> some View {
        Button(action: {
            buttonIndexToUpdate = index
            showAddItemDialog.toggle()
        }) {
            // This causes an index out of range error

//            if let selectedItem = LiveActivityItem.allCases.first(where: { $0.id == selectedItems[index].id }) {
//                // Show item preview if an item is selected
//                getItemPreview(for: selectedItem)
//            }
            if index < selectedItems.count {
                // Zeige Vorschau, wenn ein Item ausgewählt wurde
                let selectedItem = selectedItems[index]
                getItemPreview(for: selectedItem)
            } else {
                // Show "+" symbol if no item is selected
                VStack {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                .frame(width: 60, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                        .foregroundColor(.gray)
                )
            }
        }
    }

    private func getItemPreview(for item: LiveActivityItem) -> some View {
        switch item {
        case .currentGlucose:
            return AnyView(currentGlucosePreview)
        case .cob:
            return AnyView(cobPreview)
        case .iob:
            return AnyView(iobPreview)
        case .updatedLabel:
            return AnyView(updatedLabelPreview)
        }
    }

    private var dummyChart: some View {
        Chart {
            ForEach(glucoseData) { data in
                PointMark(
                    x: .value("Time", data.time),
                    y: .value("Glucose Level", data.glucoseLevel)
                ).foregroundStyle(.green.gradient).symbolSize(15)
            }
        }
        .chartPlotStyle { plotContent in
            plotContent
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.cyan.opacity(0.15))
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine(stroke: .init(lineWidth: 0.2, dash: [2, 3])).foregroundStyle(Color.primary)
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 40 ... 200)
        .chartXAxis {
            AxisMarks(position: .automatic) { _ in
                AxisGridLine(stroke: .init(lineWidth: 0.2, dash: [2, 3])).foregroundStyle(Color.primary)
            }
        }
        .chartXAxis(.hidden)
        .frame(height: 100)
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

    private func loadOrder() {
        if let savedItems = UserDefaults.standard.loadLiveActivityOrder() {
            selectedItems = savedItems
        } else {
            selectedItems = LiveActivityItem.defaultItems
            saveOrder()
        }
        print("Loaded order: \(selectedItems.map(\.rawValue))")
        updateVisibilityForSelectedItems()
    }

    private func saveOrder() {
        print("Saving order: \(selectedItems.map(\.rawValue))")
        UserDefaults.standard.saveLiveActivityOrder(selectedItems)
    }

    private func addItem(_ item: LiveActivityItem) {
        setItemVisibility(item: item, isVisible: true)
        selectedItems.append(item)
        saveOrder()
    }

    private func removeItem(_ item: LiveActivityItem) {
        setItemVisibility(item: item, isVisible: false)
        selectedItems.removeAll { $0 == item }
        saveOrder()
    }

    private func setItemVisibility(item: LiveActivityItem, isVisible: Bool) {
        switch item {
        case .currentGlucose:
            state.showCurrentGlucose = isVisible
        case .iob:
            state.showIOB = isVisible
        case .cob:
            state.showCOB = isVisible
        case .updatedLabel:
            state.showUpdatedLabel = isVisible
        }
    }

    private func updateVisibilityForSelectedItems() {
        for item in selectedItems {
            setItemVisibility(item: item, isVisible: true)
        }
        let allItems = LiveActivityItem.allCases
        let hiddenItems = allItems.filter { !selectedItems.contains($0) }
        for item in hiddenItems {
            setItemVisibility(item: item, isVisible: false)
        }
    }
}

struct DropViewDelegate: DropDelegate {
    let item: LiveActivityItem
    @Binding var items: [LiveActivityItem]
    @Binding var draggingItem: LiveActivityItem?

    func dropEntered(info _: DropInfo) {
        guard let draggingItem = draggingItem else { return }

        if draggingItem != item {
            let fromIndex = items.firstIndex(of: draggingItem)!
            let toIndex = items.firstIndex(of: item)!

            withAnimation {
                items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            }

            // Save to User Defaults
            saveOrder()

            // Trigger Live Activity Update
            Foundation.NotificationCenter.default.post(name: .liveActivityOrderDidChange, object: nil)
        }
    }

    func performDrop(info _: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }

    private func saveOrder() {
        UserDefaults.standard.saveLiveActivityOrder(items)
    }
}

// Extension for UserDefaults to save and load the order
extension UserDefaults {
    private enum Keys {
        static let liveActivityOrder = "liveActivityOrder"
    }

    func saveLiveActivityOrder(_ items: [LiveActivityItem]) {
        let itemStrings = items.map(\.rawValue)
        set(itemStrings, forKey: Keys.liveActivityOrder)
    }

    func loadLiveActivityOrder() -> [LiveActivityItem]? {
        if let itemStrings = array(forKey: Keys.liveActivityOrder) as? [String] {
            return itemStrings.compactMap { LiveActivityItem(rawValue: $0) }
        }
        return nil
    }
}

// Enum to represent each live activity item
enum LiveActivityItem: String, CaseIterable, Identifiable {
    case currentGlucose
    case iob
    case cob
    case updatedLabel

    var id: String { rawValue }

    static var defaultItems: [LiveActivityItem] {
        [.currentGlucose, .iob, .cob, .updatedLabel]
    }

    var displayName: String {
        switch self {
        case .currentGlucose:
            return "Current Glucose"
        case .iob:
            return "IOB"
        case .cob:
            return "COB"
        case .updatedLabel:
            return "Updated Label"
        }
    }
}

struct DummyChart: Identifiable {
    let id = UUID()
    let time: Double // Time in hours
    let glucoseLevel: Double // Glucose level in mg/dL
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
