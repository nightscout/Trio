# Trio AI Insights Feature Documentation

## Overview

This document provides a comprehensive history and specification of the AI Insights feature implemented in Trio, an open-source automated insulin delivery (AID) iOS application. The AI Insights feature integrates Claude AI (Anthropic) to provide intelligent analysis of glucose data, pattern recognition, and personalized recommendations.

---

## Table of Contents

1. [Implementation History](#implementation-history)
2. [Architecture Overview](#architecture-overview)
3. [Feature Specifications](#feature-specifications)
4. [File Structure](#file-structure)
5. [Data Flow](#data-flow)
6. [API Integration](#api-integration)
7. [Security Considerations](#security-considerations)
8. [Future Enhancements](#future-enhancements)

---

## Implementation History

### Phase 1: Core AI Infrastructure

**Date:** Initial Implementation

**Changes:**
- Created `AIInsightsConfig` module following Trio's MVVM architecture pattern
- Implemented `ClaudeAPIService.swift` for Claude API communication
- Added secure API key storage using iOS Keychain
- Created base UI with navigation to AI features from Settings

**Files Created:**
- `Trio/Sources/Modules/AIInsightsConfig/AIInsightsConfigDataFlow.swift`
- `Trio/Sources/Modules/AIInsightsConfig/AIInsightsConfigStateModel.swift`
- `Trio/Sources/Modules/AIInsightsConfig/AIInsightsConfigProvider.swift`
- `Trio/Sources/Modules/AIInsightsConfig/View/AIInsightsConfigRootView.swift`
- `Trio/Sources/Services/ClaudeAPIService.swift`

### Phase 2: Health Data Export

**Changes:**
- Created `HealthDataExporter.swift` to extract data from Core Data
- Implemented glucose reading export from `GlucoseStored` entity
- Added carb entry export from `CarbEntryStored` entity
- Fixed bolus data retrieval (was querying wrong entity)
- Added loop state export from `OrefDetermination` entity

**Bug Fix:**
- Original implementation queried `PumpEventStored` with `type == "bolus"` (lowercase)
- Actual database value was `"Bolus"` (capitalized)
- Fixed by fetching directly from `BolusStored` entity like `BolusStatsSetup.swift`

### Phase 3: Treatment Settings Export

**Changes:**
- Added full treatment settings export to AI analysis
- Implemented schedule fetching from OpenAPS file storage:
  - Carb ratios (`OpenAPS.Settings.carbRatios`)
  - Insulin sensitivities (`OpenAPS.Settings.insulinSensitivities`)
  - Basal profile (`OpenAPS.Settings.basalProfile`)
  - BG targets (`OpenAPS.Settings.bgTargets`)

**Data Format:**
```
CARB RATIOS (1 unit insulin per X grams)
00:00: 1:10 | 06:00: 1:8 | 12:00: 1:10 | 18:00: 1:9

INSULIN SENSITIVITY FACTORS (1 unit drops BG by X mg/dL)
00:00: 45 | 06:00: 40 | 12:00: 45 | 18:00: 42
```

### Phase 4: Raw Loop Data Export

**Changes:**
- Added `LoopState` struct to capture OrefDetermination data
- Exports every ~5 minutes: BG, IOB, COB, temp basal rate, SMB, eventual BG
- Configurable sampling intervals (5, 10, 15 minutes)
- Added compact formatting for token efficiency

**Data Format:**
```
Time | BG | IOB | COB | TempBasal | SMB
12/10 08:15 | 125 | 2.50 | 15 | 1.20 | 0.30
12/10 08:20 | 128 | 2.45 | 12 | 1.15 | -
```

### Phase 5: Quick-Add Carb Buttons

**Changes:**
- Added +5g and +10g quick-add buttons to bolus calculator
- Implemented in `TreatmentsRootView.swift`
- Added Clear button when carbs > 0
- Maintained text entry capability alongside buttons

**UI Implementation:**
```swift
HStack(spacing: 12) {
    Text("Quick Add:").font(.caption)
    Button("+5g") { state.carbs += 5 }
    Button("+10g") { state.carbs += 10 }
    if state.carbs > 0 {
        Button("Clear") { state.carbs = 0 }
    }
}
```

### Phase 6: Nightscout Integration

**Changes:**
- Created `NightscoutDataFetcher.swift` service
- Leverages existing Nightscout credentials from Keychain
- Fetches up to 90 days of historical data
- Added toggle in AI settings to enable/disable Nightscout data source
- Falls back to local Core Data if Nightscout unavailable

**Nightscout API Endpoints Used:**
- `/api/v1/entries/sgv.json` - Glucose readings
- `/api/v1/treatments.json` - Carbs and boluses
- Authentication via SHA1-hashed API secret header

### Phase 7: Multi-Timeframe Statistics

**Changes:**
- Added statistics calculation for multiple timeframes
- Timeframes: 1 day, 3 days, 7 days, 14 days, 30 days, 90 days
- Metrics calculated:
  - Average glucose
  - Standard deviation
  - Coefficient of variation (CV%)
  - Glucose Management Indicator (GMI)
  - Time in range (TIR)
  - Time below range (TBR)
  - Time above range (TAR)
  - Time very low (<54 mg/dL)
  - Time very high (>250 mg/dL)

**Output Format:**
```
| Metric | 1 Day | 3 Days | 7 Days | 14 Days | 30 Days | 90 Days |
|--------|-------|--------|--------|---------|---------|---------|
| Avg BG | 142   | 138    | 140    | 145     | 143     | 141     |
| TIR    | 72%   | 75%    | 73%    | 70%     | 71%     | 72%     |
```

### Phase 8: Doctor Visit Report

**Changes:**
- Created comprehensive export for healthcare providers
- Includes all treatment settings with full schedules
- Multi-timeframe statistics comparison table
- Full 7-day detailed data (every reading)
- AI-generated pattern analysis and recommendations
- PDF generation capability
- Text and PDF sharing options

**Report Sections:**
1. Executive Summary
2. Current Treatment Settings
3. Multi-Timeframe Statistics
4. Trend Analysis
5. Time-of-Day Patterns
6. Settings Recommendations
7. Safety Concerns
8. Discussion Points for Provider

---

## Architecture Overview

### Module Structure

```
AIInsightsConfig/
├── AIInsightsConfigDataFlow.swift    # Protocols and configuration
├── AIInsightsConfigStateModel.swift  # Business logic and state
├── AIInsightsConfigProvider.swift    # Dependency injection
├── HealthDataExporter.swift          # Data extraction and formatting
├── NightscoutDataFetcher.swift       # Nightscout API integration
└── View/
    └── AIInsightsConfigRootView.swift # All UI views
```

### Design Patterns

- **MVVM Architecture**: Following Trio's established patterns
- **Dependency Injection**: Using Swinject (`@Injected()` property wrapper)
- **BaseView/BaseStateModel**: Inheriting from Trio's base classes
- **Combine Framework**: For reactive data flow

---

## Feature Specifications

### 1. Quick Analysis

**Purpose:** Instant AI-powered insights from recent data

**Data Scope:**
- Last 24 hours of loop data (15-min intervals)
- Last 24 hours of carb entries
- 7-day statistics summary
- All treatment settings

**Output Format:**
- Overview section
- Key Patterns section
- Concerns section
- Quick Tip section

### 2. Ask Claude (Chat)

**Purpose:** Interactive Q&A about glucose data

**Features:**
- Multi-turn conversation support
- Context maintained across messages
- Example question suggestions
- Clear chat functionality

**Data Context:**
- Injected on first message
- Last 6 hours of detailed loop data
- Full settings and statistics

### 3. Weekly Report

**Purpose:** Comprehensive shareable analysis

**Data Scope:**
- Full 7 days of loop data (15-min intervals)
- All carb entries
- All bolus events
- Complete statistics

**Output Sections:**
- Summary
- Pattern Analysis
- What's Working Well
- Areas for Improvement
- Recommendations

### 4. Doctor Visit Report

**Purpose:** Professional export for healthcare providers

**Data Scope:**
- Up to 90 days (with Nightscout)
- Every glucose reading (5-min intervals)
- All treatment settings with schedules
- Multi-timeframe statistics

**Output Formats:**
- Shareable text
- PDF document

**Output Sections:**
- Executive Summary
- Current Treatment Settings
- Multi-Timeframe Statistics Table
- Detailed 7-Day Data
- AI Pattern Analysis
- Settings Recommendations
- Safety Concerns
- Discussion Points

---

## File Structure

### Core Files

| File | Purpose | Lines |
|------|---------|-------|
| `ClaudeAPIService.swift` | Claude API communication | ~150 |
| `HealthDataExporter.swift` | Data extraction and formatting | ~1000 |
| `NightscoutDataFetcher.swift` | Nightscout API integration | ~220 |
| `AIInsightsConfigStateModel.swift` | State management | ~530 |
| `AIInsightsConfigRootView.swift` | All UI views | ~920 |

### Data Structures

```swift
struct ExportedData {
    let glucoseReadings: [GlucoseReading]
    let carbEntries: [CarbEntry]
    let bolusEvents: [BolusEvent]
    let loopStates: [LoopState]
    let settings: SettingsSummary
    let statistics: Statistics
    let multiTimeframeStats: MultiTimeframeStatistics?
}

struct LoopState {
    let date: Date
    let glucose: Decimal
    let iob: Decimal
    let cob: Int
    let tempBasalRate: Decimal
    let scheduledBasalRate: Decimal
    let smbDelivered: Decimal
    let eventualBG: Decimal?
    let insulinReq: Decimal
    let reason: String?
}

struct MultiTimeframeStatistics {
    let day1: TimeframeStat?
    let day3: TimeframeStat?
    let day7: TimeframeStat?
    let day14: TimeframeStat?
    let day30: TimeframeStat?
    let day90: TimeframeStat?
}
```

---

## Data Flow

### Local Data Flow
```
Core Data Entities
    ├── GlucoseStored
    ├── CarbEntryStored
    ├── BolusStored
    └── OrefDetermination
          ↓
    HealthDataExporter
          ↓
    ExportedData struct
          ↓
    formatForPrompt()
          ↓
    ClaudeAPIService
          ↓
    Claude API
          ↓
    AI Response
          ↓
    UI Display
```

### Nightscout Data Flow
```
Keychain (URL + Secret)
          ↓
    NightscoutDataFetcher
          ↓
    Nightscout API
    ├── /api/v1/entries/sgv.json
    └── /api/v1/treatments.json
          ↓
    FetchedData struct
          ↓
    HealthDataExporter
          ↓
    (continues as above)
```

---

## API Integration

### Claude API

**Endpoint:** `https://api.anthropic.com/v1/messages`

**Model:** `claude-sonnet-4-20250514`

**Headers:**
```
x-api-key: [user's API key]
anthropic-version: 2023-06-01
Content-Type: application/json
```

**Request Format:**
```json
{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 4096,
    "system": "[safety system prompt]",
    "messages": [
        {"role": "user", "content": "[data + question]"}
    ]
}
```

### Nightscout API

**Authentication:** SHA1-hashed API secret in `api-secret` header

**Endpoints:**
- `GET /api/v1/entries/sgv.json?count=1600&find[dateString][$gt]=...`
- `GET /api/v1/treatments.json?find[insulin][$exists]=true&count=5000`

---

## Security Considerations

### API Key Storage
- Stored in iOS Keychain (not UserDefaults)
- Key: `AIInsightsConfig.claudeAPIKey`
- Never logged or displayed in plain text
- Toggle to show/hide in settings

### Nightscout Credentials
- Reuses existing Nightscout configuration
- Stored in Keychain by NightscoutConfig module
- SHA1 hashed before transmission

### Data Privacy
- All processing done on-device until sent to Claude
- No data stored on external servers (except Claude API call)
- User controls when analysis is triggered

### Safety Guidelines in System Prompt
```
IMPORTANT SAFETY GUIDELINES:
- You are allowed to recommend specific insulin doses - but only
  after careful consideration and conservatively
- Assume large spikes without carbs entered are missed meals
- Note that you are not the user's doctor
- Do not recommend doses that could cause dangerous hypoglycemia
```

---

## Future Enhancements

### High Priority

#### 1. Meal Photo Carb Estimation
**Description:** Use Claude's vision capabilities to estimate carbs from food photos
**Implementation:**
- Add camera/photo picker to carb entry
- Send image to Claude with prompt for carb estimation
- Pre-fill carb field with AI estimate
- Allow user to adjust before confirming

**Complexity:** Medium
**Value:** High - reduces carb counting burden

#### 2. Predictive Alerts
**Description:** AI-powered prediction of upcoming glucose events
**Implementation:**
- Background analysis of recent patterns
- Predict likely hypo/hyper events 30-60 min ahead
- Push notification with preventive suggestions
- "Based on your pattern, you may go low around 2 PM"

**Complexity:** High
**Value:** High - proactive vs reactive management

#### 3. Smart Notifications
**Description:** Contextual AI messages based on current state
**Implementation:**
- Analyze current BG trend + recent history
- Generate relevant tips at key moments
- "You're rising after lunch - last 3 days you needed +10% bolus"

**Complexity:** Medium
**Value:** Medium - reinforces learning

### Medium Priority

#### 4. Siri Integration
**Description:** Voice-activated AI insights
**Implementation:**
- Add App Intents for common queries
- "Hey Siri, ask Trio about my morning pattern"
- "Hey Siri, get my Trio weekly report"
- Shortcuts app integration

**Complexity:** Medium
**Value:** Medium - hands-free convenience

#### 5. Morning Briefing Widget
**Description:** Daily summary widget/notification
**Implementation:**
- Generate overnight summary each morning
- Include: overnight TIR, any events, day ahead forecast
- iOS widget with key metrics
- Optional push notification

**Complexity:** Medium
**Value:** Medium - daily engagement

#### 6. Settings Auto-Tune Suggestions
**Description:** AI analyzes patterns and suggests setting changes
**Implementation:**
- Identify consistent patterns (e.g., always high at 6 AM)
- Calculate suggested basal/ratio adjustments
- Present with confidence level and reasoning
- One-tap to apply (with confirmation)

**Complexity:** High
**Value:** High - simplifies optimization

### Lower Priority

#### 7. Exercise Pattern Recognition
**Description:** Learn user's exercise patterns and effects
**Implementation:**
- Detect exercise from CGM patterns or HealthKit
- Learn personal exercise effects on BG
- Suggest pre-exercise carbs or temp targets
- "Looks like you're about to exercise - consider 15g carbs"

**Complexity:** High
**Value:** Medium - helps active users

#### 8. Menstrual Cycle Awareness
**Description:** Track and predict cycle-related BG changes
**Implementation:**
- Optional cycle tracking integration
- Learn personal patterns per cycle phase
- Adjust expectations and suggestions
- "You're in luteal phase - expect 10-15% higher BG"

**Complexity:** Medium
**Value:** Medium - helps subset of users

#### 9. Stress/Sleep Correlation
**Description:** Correlate external factors with BG
**Implementation:**
- HealthKit integration for sleep data
- Optional stress/mood logging
- Identify correlations over time
- "Poor sleep last night - watch for insulin resistance today"

**Complexity:** Medium
**Value:** Low-Medium - interesting insights

#### 10. Community Insights (Anonymous)
**Description:** Learn from aggregate community patterns
**Implementation:**
- Opt-in anonymous data sharing
- "Users with similar settings found success with..."
- Benchmark against similar users
- Privacy-preserving aggregation

**Complexity:** Very High
**Value:** Medium - requires infrastructure

### Technical Improvements

#### 11. Offline Analysis
**Description:** Basic analysis without internet
**Implementation:**
- On-device ML model for pattern detection
- Basic statistics and trends locally
- Queue requests for when online
- Reduced but functional capability offline

**Complexity:** Very High
**Value:** Medium - edge case but important

#### 12. Cost Optimization
**Description:** Reduce API costs through efficiency
**Implementation:**
- Smart caching of responses
- Summarize data more aggressively for simple queries
- Use Claude Haiku for simpler requests
- Batch requests where possible

**Complexity:** Medium
**Value:** Low - cost savings for heavy users

#### 13. Multi-Language Support
**Description:** AI responses in user's preferred language
**Implementation:**
- Detect device language
- Add language preference to system prompt
- Ensure medical terminology accuracy per language

**Complexity:** Low
**Value:** Medium - accessibility

---

## Appendix: Commit History

```
9aa5921bc Add Nightscout integration and Doctor Visit report to AI Insights
935dc7a10 Add quick-add carb buttons to Action Button carbs modal
bd16d7b5a Add quick-add carb buttons (+5g, +10g) to bolus calculator
ca9d37689 Add full treatment settings export to AI analysis
591329ac5 Enhance AI analysis with raw loop data and improved formatting
```

---

## Document Information

- **Version:** 1.0
- **Last Updated:** December 10, 2025
- **Author:** Claude AI (Implementation Assistant)
- **Repository:** Trio iOS App
- **Branch:** claude/add-ai-insights-feature-01MddDMcSDP7SXKRMQRSYxzV
