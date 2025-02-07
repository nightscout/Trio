//
//  LiveActivityBGAndTrendView.swift
//  Trio
//
//  Created by Cengiz Deniz on 17.10.24.
//
import Foundation
import SwiftUI
import WidgetKit

struct LiveActivityBGAndTrendView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    var size: Size
    var glucoseColor: Color

    var body: some View {
        let (view, _) = bgAndTrend(context: context, size: size, glucoseColor: glucoseColor)
        return view
    }
}
