import ClockKit
import SwiftUI

class ComplicationController: NSObject, CLKComplicationDataSource {
    // MARK: - Complication Configuration

    func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
        let descriptors = [
            CLKComplicationDescriptor(
                identifier: "trio_glucose",
                displayName: "Trio Glucose",
                supportedFamilies: [
                    .graphicCorner,
                    .graphicCircular,
                    .graphicRectangular,
                    .graphicExtraLarge,
                    .modularSmall,
                    .modularLarge,
                    .utilitarianSmall,
                    .utilitarianSmallFlat,
                    .utilitarianLarge,
                    .circularSmall
                ]
            )
        ]
        handler(descriptors)
    }

    func handleSharedComplicationDescriptors(_: [CLKComplicationDescriptor]) {}

    // MARK: - Timeline Configuration

    func getTimelineEndDate(for _: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        // Provide timeline entries for the next hour
        handler(Date().addingTimeInterval(60 * 60))
    }

    func getPrivacyBehavior(for _: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
        handler(.showOnLockScreen)
    }

    // MARK: - Timeline Population

    func getCurrentTimelineEntry(
        for complication: CLKComplication,
        withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void
    ) {
        let template = createTemplate(for: complication.family)
        if let template = template {
            let entry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
            handler(entry)
        } else {
            handler(nil)
        }
    }

    func getTimelineEntries(
        for complication: CLKComplication,
        after date: Date,
        limit: Int,
        withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void
    ) {
        // Create future entries to show staleness
        var entries: [CLKComplicationTimelineEntry] = []

        // Add entries every 5 minutes to update staleness indicator
        for i in 1 ... min(limit, 12) {
            let futureDate = date.addingTimeInterval(Double(i) * 5 * 60)
            if let template = createTemplate(for: complication.family, at: futureDate) {
                entries.append(CLKComplicationTimelineEntry(date: futureDate, complicationTemplate: template))
            }
        }

        handler(entries)
    }

    // MARK: - Sample Templates

    func getLocalizableSampleTemplate(
        for complication: CLKComplication,
        withHandler handler: @escaping (CLKComplicationTemplate?) -> Void
    ) {
        let sampleData = ComplicationData(
            glucose: "120",
            trend: "→",
            delta: "+2",
            glucoseDate: Date(),
            lastLoopDate: Date(),
            iob: "1.5",
            cob: "20",
            eventualBG: "115"
        )
        handler(createTemplate(for: complication.family, with: sampleData))
    }

    // MARK: - Template Creation

    private func createTemplate(for family: CLKComplicationFamily, at date: Date = Date()) -> CLKComplicationTemplate? {
        let data = ComplicationData.load()
        return createTemplate(for: family, with: data, at: date)
    }

    private func createTemplate(
        for family: CLKComplicationFamily,
        with data: ComplicationData?,
        at date: Date = Date()
    ) -> CLKComplicationTemplate? {
        guard let data = data else {
            return createPlaceholderTemplate(for: family)
        }

        // Calculate staleness based on provided date
        let minutesAgo: Int
        if let glucoseDate = data.glucoseDate {
            minutesAgo = Int(date.timeIntervalSince(glucoseDate) / 60)
        } else {
            minutesAgo = 999
        }
        let isStale = minutesAgo > 15
        let isVeryStale = minutesAgo > 30

        let tintColor: UIColor = isVeryStale ? .red : (isStale ? .yellow : .green)

        switch family {
        case .graphicCorner:
            return createGraphicCornerTemplate(data: data, tintColor: tintColor)

        case .graphicCircular:
            return createGraphicCircularTemplate(data: data, tintColor: tintColor, minutesAgo: minutesAgo)

        case .graphicRectangular:
            return createGraphicRectangularTemplate(data: data, tintColor: tintColor, minutesAgo: minutesAgo)

        case .graphicExtraLarge:
            return createGraphicExtraLargeTemplate(data: data, tintColor: tintColor)

        case .modularSmall:
            return createModularSmallTemplate(data: data, tintColor: tintColor)

        case .modularLarge:
            return createModularLargeTemplate(data: data, minutesAgo: minutesAgo)

        case .utilitarianSmall, .utilitarianSmallFlat:
            return createUtilitarianSmallTemplate(data: data)

        case .utilitarianLarge:
            return createUtilitarianLargeTemplate(data: data, minutesAgo: minutesAgo)

        case .circularSmall:
            return createCircularSmallTemplate(data: data)

        default:
            return nil
        }
    }

    // MARK: - Graphic Corner

    private func createGraphicCornerTemplate(data: ComplicationData, tintColor: UIColor) -> CLKComplicationTemplate {
        let glucoseText = CLKSimpleTextProvider(text: data.glucose)
        glucoseText.tintColor = tintColor

        let trendText = CLKSimpleTextProvider(text: data.trend)
        trendText.tintColor = tintColor

        let deltaText = CLKSimpleTextProvider(text: data.delta)

        return CLKComplicationTemplateGraphicCornerStackText(
            innerTextProvider: deltaText,
            outerTextProvider: CLKTextProvider(format: "%@ %@", glucoseText, trendText)
        )
    }

    // MARK: - Graphic Circular

    private func createGraphicCircularTemplate(
        data: ComplicationData,
        tintColor: UIColor,
        minutesAgo: Int
    ) -> CLKComplicationTemplate {
        // Use a gauge to show time since last reading (fills up as it gets stale)
        let fraction = min(Float(minutesAgo) / 15.0, 1.0)

        let gaugeProvider = CLKSimpleGaugeProvider(
            style: .ring,
            gaugeColor: tintColor,
            fillFraction: 1.0 - fraction
        )

        let glucoseText = CLKSimpleTextProvider(text: data.glucose)
        let trendText = CLKSimpleTextProvider(text: data.trend)

        return CLKComplicationTemplateGraphicCircularOpenGaugeSimpleText(
            gaugeProvider: gaugeProvider,
            bottomTextProvider: trendText,
            centerTextProvider: glucoseText
        )
    }

    // MARK: - Graphic Rectangular

    private func createGraphicRectangularTemplate(
        data: ComplicationData,
        tintColor: UIColor,
        minutesAgo: Int
    ) -> CLKComplicationTemplate {
        let headerText = CLKSimpleTextProvider(text: "Trio")
        headerText.tintColor = tintColor

        let glucoseText = CLKSimpleTextProvider(text: "\(data.glucose) \(data.trend)")
        glucoseText.tintColor = tintColor

        var body1Text: String = data.delta
        if let iob = data.iob {
            body1Text += " • IOB: \(iob)"
        }
        let body1Provider = CLKSimpleTextProvider(text: body1Text)

        var body2Text = ""
        if let cob = data.cob {
            body2Text = "COB: \(cob)"
        }
        if minutesAgo < 999 {
            if !body2Text.isEmpty { body2Text += " • " }
            body2Text += "\(minutesAgo)m ago"
        }
        let body2Provider = CLKSimpleTextProvider(text: body2Text)

        return CLKComplicationTemplateGraphicRectangularStandardBody(
            headerTextProvider: headerText,
            body1TextProvider: CLKTextProvider(format: "%@ %@", glucoseText, body1Provider),
            body2TextProvider: body2Provider
        )
    }

    // MARK: - Graphic Extra Large

    private func createGraphicExtraLargeTemplate(data: ComplicationData, tintColor: UIColor) -> CLKComplicationTemplate {
        let glucoseText = CLKSimpleTextProvider(text: data.glucose)
        glucoseText.tintColor = tintColor

        let trendText = CLKSimpleTextProvider(text: data.trend)
        trendText.tintColor = tintColor

        return CLKComplicationTemplateGraphicExtraLargeCircularStackText(
            line1TextProvider: glucoseText,
            line2TextProvider: trendText
        )
    }

    // MARK: - Modular Small

    private func createModularSmallTemplate(data: ComplicationData, tintColor: UIColor) -> CLKComplicationTemplate {
        let glucoseText = CLKSimpleTextProvider(text: data.glucose)
        glucoseText.tintColor = tintColor

        return CLKComplicationTemplateModularSmallStackText(
            line1TextProvider: glucoseText,
            line2TextProvider: CLKSimpleTextProvider(text: data.trend)
        )
    }

    // MARK: - Modular Large

    private func createModularLargeTemplate(data: ComplicationData, minutesAgo: Int) -> CLKComplicationTemplate {
        let headerText = CLKSimpleTextProvider(text: "Trio Glucose")

        let glucoseText = CLKSimpleTextProvider(text: "\(data.glucose) \(data.trend) \(data.delta)")

        var detailText = ""
        if let iob = data.iob {
            detailText += "IOB: \(iob)"
        }
        if let cob = data.cob {
            if !detailText.isEmpty { detailText += " | " }
            detailText += "COB: \(cob)"
        }
        let body1Provider = CLKSimpleTextProvider(text: detailText)

        let timeText = minutesAgo < 999 ? "\(minutesAgo) min ago" : "No data"
        let body2Provider = CLKSimpleTextProvider(text: timeText)

        return CLKComplicationTemplateModularLargeStandardBody(
            headerTextProvider: headerText,
            body1TextProvider: CLKTextProvider(format: "%@ • %@", glucoseText, body1Provider),
            body2TextProvider: body2Provider
        )
    }

    // MARK: - Utilitarian Small

    private func createUtilitarianSmallTemplate(data: ComplicationData) -> CLKComplicationTemplate {
        let text = CLKSimpleTextProvider(text: "\(data.glucose)\(data.trend)")
        return CLKComplicationTemplateUtilitarianSmallFlat(textProvider: text)
    }

    // MARK: - Utilitarian Large

    private func createUtilitarianLargeTemplate(data: ComplicationData, minutesAgo: Int) -> CLKComplicationTemplate {
        var text = "\(data.glucose) \(data.trend) \(data.delta)"
        if minutesAgo < 999, minutesAgo > 5 {
            text += " (\(minutesAgo)m)"
        }
        return CLKComplicationTemplateUtilitarianLargeFlat(
            textProvider: CLKSimpleTextProvider(text: text)
        )
    }

    // MARK: - Circular Small

    private func createCircularSmallTemplate(data: ComplicationData) -> CLKComplicationTemplate {
        CLKComplicationTemplateCircularSmallStackText(
            line1TextProvider: CLKSimpleTextProvider(text: data.glucose),
            line2TextProvider: CLKSimpleTextProvider(text: data.trend)
        )
    }

    // MARK: - Placeholder Template

    private func createPlaceholderTemplate(for family: CLKComplicationFamily) -> CLKComplicationTemplate? {
        let placeholder = ComplicationData(
            glucose: "---",
            trend: "→",
            delta: "--",
            glucoseDate: nil,
            lastLoopDate: nil,
            iob: nil,
            cob: nil,
            eventualBG: nil
        )
        return createTemplate(for: family, with: placeholder)
    }
}
