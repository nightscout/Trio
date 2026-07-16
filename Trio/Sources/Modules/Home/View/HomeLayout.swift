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
    /// stats banner slot below the adjustment panel (multi-use panel later)
    static let statsBannerHeight: CGFloat = 60
    /// clear air above, between, and below the bottom-zone panels
    static let bottomZonePadding: CGFloat = 10
    static var bottomZoneHeight: CGFloat { bottomPanelHeight + statsBannerHeight + 3 * bottomZonePadding }
    /// minimum usable chart height; must stay below the natural SE allocation
    /// (598 − header − meal slot − bottom zone = 238) or the bottom zone overflows
    static let chartMinHeight: CGFloat = 220
}
