import Foundation
import Testing
@testable import Trio

@Suite("Settings Search Navigation") struct SettingsSearchTests {
    @Test("Searching 'Dynamic ISF' finds the Dynamic Settings screen") func searchDynamicISF() {
        let results = SettingItems.filteredItems(searchText: "Dynamic ISF")
        #expect(!results.isEmpty)
        let match = results.first { $0.matchedContent == "Dynamic ISF" }
        #expect(match != nil)
        #expect(match?.settingItem.view == .dynamicISF)
        #expect(match?.scrollLabel == "Dynamic ISF")
    }

    @Test("All scrollTargetLabels have valid non-empty targets") func scrollTargetLabelsNonEmpty() {
        for item in SettingItems.allItems {
            guard let labels = item.scrollTargetLabels else { continue }
            for (key, value) in labels {
                #expect(!value.isEmpty)
                #expect(item.searchContents?.contains(key) == true)
            }
        }
    }

    @Test("Every searchContents entry produces at least one result") func allSearchContentsAreSearchable() {
        for item in SettingItems.allItems {
            guard let contents = item.searchContents else { continue }
            for content in contents {
                let results = SettingItems.filteredItems(searchText: content)
                #expect(!results.isEmpty)
            }
        }
    }

    @Test("SearchResultTarget is Hashable and equatable by value") func searchResultTargetHashable() {
        let a = SearchResultTarget(screen: .dynamicISF, scrollLabel: "Dynamic ISF")
        let b = SearchResultTarget(screen: .dynamicISF, scrollLabel: "Dynamic ISF")
        let c = SearchResultTarget(screen: .dynamicISF, scrollLabel: "Adjust Basal")
        #expect(a == b)
        #expect(a != c)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("SettingsSearchHighlight starts nil and accepts assignments")
    @MainActor func highlightStateTransitions() {
        let highlight = SettingsSearchHighlight()
        #expect(highlight.highlightedSetting == nil)

        highlight.highlightedSetting = "Dynamic ISF"
        #expect(highlight.highlightedSetting == "Dynamic ISF")

        highlight.highlightedSetting = nil
        #expect(highlight.highlightedSetting == nil)
    }

    @Test("SettingsSearchHighlight can be set and cleared in sequence")
    @MainActor func highlightSequentialUpdates() async {
        let highlight = SettingsSearchHighlight()

        highlight.highlightedSetting = "First Setting"
        #expect(highlight.highlightedSetting == "First Setting")

        highlight.highlightedSetting = "Second Setting"
        #expect(highlight.highlightedSetting == "Second Setting")

        highlight.highlightedSetting = nil
        #expect(highlight.highlightedSetting == nil)
    }
}
