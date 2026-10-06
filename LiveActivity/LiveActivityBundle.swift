import SwiftUI
import WidgetKit

@main struct LiveActivityBundle: WidgetBundle {
    var body: some Widget {
        LiveActivity()
        #if canImport(AlarmKit)
            if #available(iOS 26.0, *) {
                PreBolusAlarmWidget()
            }
        #endif
    }
}
