import ClockKit
import SwiftUI

class ComplicationController: NSObject, CLKComplicationDataSource {
    // MARK: - Complication Configuration

    func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
        let descriptors = [
            CLKComplicationDescriptor(
                identifier: "complication",
                displayName: "Open-iAPS",
                supportedFamilies: [
                    .graphicCorner,
                    .graphicCircular,
                    .modularSmall,
                    .utilitarianSmall,
                    .circularSmall
                ]
            )
        ]

        // Call the handler with the currently supported complication descriptors
        handler(descriptors)
    }

    func handleSharedComplicationDescriptors(_: [CLKComplicationDescriptor]) {
        // Do any necessary work to support these newly shared complication descriptors
    }

    // MARK: - Timeline Configuration

    func getTimelineEndDate(for _: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        // Call the handler with the last entry date you can currently provide or nil if you can't support future timelines
        handler(nil)
    }

    func getPrivacyBehavior(for _: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
        // Call the handler with your desired behavior when the device is locked
        handler(.showOnLockScreen)
    }

    // MARK: - Timeline Population

    func getCurrentTimelineEntry(
        for complication: CLKComplication,
        withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void
    ) {
        switch complication.family {
        case .graphicCorner:
            guard let image = UIImage(named: "Complication/Graphic Corner") else {
                handler(nil)
                return
            }
            let template = CLKComplicationTemplateGraphicCornerTextImage(
                textProvider: CLKTextProvider(format: "%@", "Open-iAPS"),
                imageProvider: CLKFullColorImageProvider(fullColorImage: image)
            )
            let timelineEntry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
            handler(timelineEntry)
        case .modularSmall:
            let template = CLKComplicationTemplateModularSmallRingText(
                textProvider: CLKTextProvider(format: "%@", "FAX"),
                fillFraction: 1,
                ringStyle: .closed
            )

            let timelineEntry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
            handler(timelineEntry)
        case .utilitarianSmall:
            guard let image = UIImage(named: "Complication/Utilitarian") else {
                handler(nil)
                return
            }
            let template = CLKComplicationTemplateUtilitarianSmallSquare(
                imageProvider: CLKImageProvider(onePieceImage: image)
            )
            let timelineEntry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
            handler(timelineEntry)
        case .circularSmall:
            let template =
                CLKComplicationTemplateCircularSmallSimpleText(textProvider: CLKTextProvider(format: "%@", "FAX"))
            let timelineEntry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
            handler(timelineEntry)
        default:
            handler(nil)
        }
    }

    func getTimelineEntries(
        for _: CLKComplication,
        after _: Date,
        limit _: Int,
        withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void
    ) {
        handler(nil)
    }

    // MARK: - Sample Templates

    func getLocalizableSampleTemplate(
        for _: CLKComplication,
        withHandler handler: @escaping (CLKComplicationTemplate?) -> Void
    ) {
        handler(nil)
    }
}
