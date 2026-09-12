import Foundation
import Testing
@testable import Trio

@Suite("Max IOB Suggestion") struct MaxIOBSuggestionTests {
    private let setting = PickerSettingsProvider.shared.settings.maxIOB

    @Test("Flat profile sums to rate times 24") func flatProfile() {
        let total = Onboarding.StateModel.totalDailyBasal(segments: [(startMinutes: 0, rate: 1)])
        #expect(total == 24)
    }

    @Test("Segments are summed by duration, whatever order they arrive in") func segmentedProfile() {
        // 00:00 1.0 U/hr for 6h, 06:00 0.5 U/hr for 6h, 12:00 2.0 U/hr for 12h = 6 + 3 + 24
        let segments = [
            (startMinutes: 720, rate: Decimal(2)),
            (startMinutes: 0, rate: Decimal(1)),
            (startMinutes: 360, rate: Decimal(0.5))
        ]
        #expect(Onboarding.StateModel.totalDailyBasal(segments: segments) == 33)
    }

    @Test("An empty profile totals zero") func emptyProfile() {
        #expect(Onboarding.StateModel.totalDailyBasal(segments: []) == 0)
    }

    @Test("Suggestion is a third of total daily basal") func suggestionIsOneThird() {
        // 24 U/day of basal, picker step 1 U -> 8 U
        let suggestion = Onboarding.StateModel.suggestedMaxIOB(totalDailyBasal: 24, setting: setting)
        #expect(suggestion == 8)
    }

    @Test("Suggestion snaps to the picker step") func suggestionSnapsToStep() {
        // 25 U/day / 3 = 8.33 -> 8 with a 1 U step
        #expect(Onboarding.StateModel.suggestedMaxIOB(totalDailyBasal: 25, setting: setting) == 8)
        // 26 U/day / 3 = 8.67 -> 9
        #expect(Onboarding.StateModel.suggestedMaxIOB(totalDailyBasal: 26, setting: setting) == 9)
    }

    @Test("Suggestion stays inside the picker bounds") func suggestionRespectsBounds() {
        let huge = Onboarding.StateModel.suggestedMaxIOB(totalDailyBasal: 1000, setting: setting)
        #expect(huge == setting.max)
        let none = Onboarding.StateModel.suggestedMaxIOB(totalDailyBasal: 0, setting: setting)
        #expect(none == setting.min)
    }
}
