import Foundation

struct FetchedNightscoutProfileStore: JSON {
    let _id: String
    let defaultProfile: String
    let startDate: String
    // TODO: what is this shit used for?
    // <<<<<<< HEAD
    let mills: Decimal
    let enteredBy: String
//    let store: [String: ScheduledNightscoutProfile]
    let created_at: String
    //=======
    let store: [String: FetchedNightscoutProfile]
    // >>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
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
