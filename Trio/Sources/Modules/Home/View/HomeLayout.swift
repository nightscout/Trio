import CoreGraphics

/// Fixed zone heights for the non-scrolling Home dashboard; the chart takes the remainder.
enum HomeLayout {
    /// header slot: pump panel / glucose bobble / loop status; includes room
    /// for the sensor arc/tag overhanging the bobble
    static let headerHeight: CGFloat = 166
    /// meal panel slot (IOB / COB / delivery rate)
    static let mealSlotHeight: CGFloat = 44
    /// shared slot for adjustment panel and bolus progress (was 8% of screen height)
    static let bottomPanelHeight: CGFloat = 60
    /// clear air above (chart x-axis labels) and below (tab bar) the bottom panel
    static let bottomZonePadding: CGFloat = 10
    static var bottomZoneHeight: CGFloat { bottomPanelHeight + 2 * bottomZonePadding }
    /// interim slot for the time-interval buttons; removed with the layout rework
    static let timeButtonsRowHeight: CGFloat = 44
    /// minimum usable chart height (basal + glucose + COB/IOB panes)
    static let chartMinHeight: CGFloat = 260
}
