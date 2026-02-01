# Removal Guide: ISF Tiers & Data Export Features

This document provides step-by-step instructions for completely removing the ISF Tiers and/or Data Export features added to Trio. Use this if the features need to be rolled back.

---

## Feature 1: ISF Sensitivity Tiers

### Files to DELETE
- `Trio/Sources/Models/InsulinSensitivityTiers.swift`
- `Trio/Sources/Modules/ISFTiersEditor/ISFTiersEditorDataFlow.swift`
- `Trio/Sources/Modules/ISFTiersEditor/ISFTiersEditorProvider.swift`
- `Trio/Sources/Modules/ISFTiersEditor/ISFTiersEditorStateModel.swift`
- `Trio/Sources/Modules/ISFTiersEditor/View/ISFTiersEditorRootView.swift`
- `Trio/Resources/json/defaults/settings/insulin_sensitivity_tiers.json`

### Files to EDIT

#### `Trio/Sources/APS/OpenAPS/Constants.swift`
- Remove the line: `static let insulinSensitivityTiers = "settings/insulin_sensitivity_tiers.json"`

#### `Trio/Sources/Models/TrioCustomOrefVariables.swift`
- Remove property: `var isfTiersEnabled: Bool`
- Remove property: `var isfTiers: [InsulinSensitivityTier]`
- Remove corresponding `CodingKeys` entries: `case isfTiersEnabled`, `case isfTiers`
- Remove these parameters from the `init()` method: `isfTiersEnabled: Bool = false, isfTiers: [InsulinSensitivityTier] = []`
- Remove the assignments in init: `self.isfTiersEnabled = isfTiersEnabled`, `self.isfTiers = isfTiers`

#### `Trio/Sources/APS/OpenAPS/OpenAPS.swift`
- In `prepareTrioCustomOrefVariables()`, remove the ISF tiers loading block:
  ```swift
  let isfTiersSettings = self.storage.retrieve(
      OpenAPS.Settings.insulinSensitivityTiers,
      as: InsulinSensitivityTiers.self
  ) ?? InsulinSensitivityTiers(enabled: false, tiers: [])
  ```
- Remove the `isfTiersEnabled:` and `isfTiers:` parameters from the `TrioCustomOrefVariables(...)` constructor call

#### `trio-oref/lib/determine-basal/determine-basal.js`
- Remove the ISF tier adjustment block (search for `isfTiersEnabled` or `isfTierLog`). It's the block starting with:
  ```javascript
  var isfTierLog = "";
  if (trio_custom_variables.isfTiersEnabled && trio_custom_variables.isfTiers ...
  ```
  Remove the entire `if` block through the closing `}`.
- After editing, rebuild the JS bundle:
  ```bash
  cd trio-oref && npx webpack --config webpack.config.js
  cp dist/determine-basal.js ../Trio/Resources/javascript/bundle/determine-basal.js
  sed -i 's/freeaps_determineBasal/trio_determineBasal/g' ../Trio/Resources/javascript/bundle/determine-basal.js
  ```

#### `Trio/Sources/Router/Screen.swift`
- Remove `case isfTiersEditor` from the `Screen` enum
- Remove the view builder case:
  ```swift
  case .isfTiersEditor:
      ISFTiersEditor.RootView(resolver: resolver)
  ```

#### `Trio/Sources/Modules/Settings/View/Subviews/AlgorithmSettings.swift`
- Remove the line: `Text("ISF Tiers").navigationLink(to: .isfTiersEditor, from: self)`

#### `Trio/Sources/Modules/Settings/SettingItems.swift`
- Remove the ISF Tiers entry from `algorithmItems`:
  ```swift
  SettingItem(
      title: "ISF Tiers",
      view: .isfTiersEditor,
      searchContents: [
          "ISF Sensitivity Tiers",
          "BG Range ISF",
          "ISF Multiplier",
          "Insulin Sensitivity Tiers"
      ],
      path: ["Algorithm", "ISF Tiers"]
  ),
  ```

### Xcode Project (`Trio.xcodeproj/project.pbxproj`)
Remove entries with these IDs:
- **PBXBuildFile**: `AA00020000000000000001B1` through `AA00020000000000000005B1`
- **PBXFileReference**: `AA00010000000000000001A1` through `AA00010000000000000005A1`
- **PBXGroup**: `AA00030000000000000001C1` (ISFTiersEditor), `AA00030000000000000002C1` (ISFTiersEditor/View)
- Remove `AA00010000000000000001A1` from the Models group children
- Remove `AA00030000000000000001C1` from the Modules group children
- Remove build file IDs from the Trio target's `PBXSourcesBuildPhase`

---

## Feature 2: Data Export

### Files to DELETE
- `Trio/Sources/Modules/DataExport/DataExportService.swift`
- `Trio/Sources/Modules/DataExport/DataExportDataFlow.swift`
- `Trio/Sources/Modules/DataExport/DataExportProvider.swift`
- `Trio/Sources/Modules/DataExport/DataExportStateModel.swift`
- `Trio/Sources/Modules/DataExport/View/DataExportRootView.swift`

### Files to EDIT

#### `Trio/Sources/Router/Screen.swift`
- Remove `case dataExport` from the `Screen` enum
- Remove the view builder case:
  ```swift
  case .dataExport:
      DataExport.RootView(resolver: resolver)
  ```

#### `Trio/Sources/Modules/Settings/View/SettingsRootView.swift`
- Remove the line: `Text("Export Data").navigationLink(to: .dataExport, from: self)`
  (Located in the "Support & Community" section, between "Share Logs" and "Submit Ticket on GitHub")

#### `Trio/Sources/Modules/Settings/SettingItems.swift`
- Remove the entire `supportItems` static property
- Remove `+ supportItems` from the `allItems` computed property

### Xcode Project (`Trio.xcodeproj/project.pbxproj`)
Remove entries with these IDs:
- **PBXBuildFile**: `AA00020000000000000006B1` through `AA0002000000000000000AB1`
- **PBXFileReference**: `AA00010000000000000006A1` through `AA0001000000000000000AA1`
- **PBXGroup**: `AA00030000000000000003C1` (DataExport), `AA00030000000000000004C1` (DataExport/View)
- Remove `AA00030000000000000003C1` from the Modules group children
- Remove build file IDs from the Trio target's `PBXSourcesBuildPhase`

---

## Quick Revert (Git)

If the features were added as separate commits, you can revert them:

```bash
# Find the commits
git log --oneline | grep -E "ISF|insulin|tiers|export|Export"

# Revert specific commits (newest first)
git revert <data-export-commit-hash>
git revert <isf-tiers-commit-hash>
```

The relevant commits on `claude/insulin-sensitivity-tiers-BJkNG`:
- `29f859e` - Add BG-range-based insulin sensitivity tiers
- `c5b9ca6` - Add data export feature for CSV export of all health data

---

*Created: February 2026*
*Branch: claude/insulin-sensitivity-tiers-BJkNG*
