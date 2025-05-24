//
// Trio
// RawFetchedProfile.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Jon B Mårtensson and Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import Foundation

struct FetchedNightscoutProfileStore: JSON {
    let _id: String
    let defaultProfile: String
    let startDate: String
    let mills: Decimal
    let enteredBy: String
    let store: [String: ScheduledNightscoutProfile]
    let created_at: String
}

struct FetchedNightscoutProfile: JSON {
    let dia: Decimal
    let carbs_hr: Int
    let delay: Decimal
    let timezone: String
    let target_low: [NightscoutTimevalue]
    let target_high: [NightscoutTimevalue]
    let sens: [NightscoutTimevalue]
    let basal: [NightscoutTimevalue]
    let carbratio: [NightscoutTimevalue]
    let units: String
}
