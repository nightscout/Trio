// Trio
// LiveActivityBGAndTrendView.swift
// Created by Deniz Cengiz on 2024-10-17.

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
