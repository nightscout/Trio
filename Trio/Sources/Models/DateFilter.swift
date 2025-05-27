//
// Trio
// DateFilter.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Jon Mårtensson and Jon B Mårtensson.
//
// Documentation available under: https://triodocs.org/

import Foundation

struct DateFilter {
    var twoHours = Date().addingTimeInterval(-2.hours.timeInterval) as NSDate
    var today = Calendar.current.startOfDay(for: Date()) as NSDate
    var day = Date().addingTimeInterval(-24.hours.timeInterval) as NSDate
    var week = Date().addingTimeInterval(-7.days.timeInterval) as NSDate
    var month = Date().addingTimeInterval(-30.days.timeInterval) as NSDate
    var total = Date().addingTimeInterval(-90.days.timeInterval) as NSDate
}
