//
//  GlucoseSmoothing.swift
//  MiaomiaoClientUI
//
//  Created by LoopKit Authors on 25/03/2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation

// https://github.com/NightscoutFoundation/xDrip/pull/828/files

// private func trendToLibreGlucose(_ measurements: [Measurement]) -> [LibreGlucose]?{

func CalculateSmothedData5Points(origtrends: [LibreGlucose]) -> [LibreGlucose] {
    // In all places in the code, there should be exactly 16 points.
    // Since that might change, and I'm doing an average of 5, then in the case of less then 5 points,
    // I'll only copy the data as is (to make sure there are reasonable values when the function returns).

    var trends = origtrends
    // this is an adoptation, doesn't follow the original directly
    if trends.count < 5 {
        for i in 0 ..< trends.count {
            trends[i].glucoseDouble = trends[i].unsmoothedGlucose
        }

        return trends
    }
    for i in 0 ..< trends.count - 4 {
        trends[i].glucoseDouble = (trends[i].unsmoothedGlucose + trends[i + 1].unsmoothedGlucose +
                                   trends[i + 2].unsmoothedGlucose +
                                   trends[i + 3].unsmoothedGlucose +
                                   trends[i + 4].unsmoothedGlucose) / 5
    }
    trends[trends.count - 4].glucoseDouble = (trends[trends.count - 4].unsmoothedGlucose +
                                              trends[trends.count - 3].unsmoothedGlucose +
                                              trends[trends.count - 2].unsmoothedGlucose +
                                              trends[trends.count - 1].unsmoothedGlucose) / 4

    trends[trends.count - 3].glucoseDouble = (trends[trends.count - 3].unsmoothedGlucose + trends[trends.count - 2].unsmoothedGlucose + trends[trends.count - 1].unsmoothedGlucose ) / 3

    trends[trends.count - 2].glucoseDouble = (trends[trends.count - 2].unsmoothedGlucose + trends[trends.count - 1].unsmoothedGlucose ) / 2

    trends[trends.count - 1].glucoseDouble = trends[trends.count - 2].glucoseDouble

    return trends
}
