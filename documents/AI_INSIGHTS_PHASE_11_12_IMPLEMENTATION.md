# AI Insights Phase 11 & 12: Why High/Low + Photo Carb Estimation

## Overview

This document details the implementation plan for two new AI Insights features:
- **Phase 11**: "Why Am I High/Low Right Now?" - Contextual analysis banner
- **Phase 12**: Meal Photo Carb Estimation - Vision-based carb counting

---

## Table of Contents

1. [Phase 11: Why Am I High/Low Right Now?](#phase-11-why-am-i-highlow-right-now)
2. [Phase 12: Meal Photo Carb Estimation](#phase-12-meal-photo-carb-estimation)
3. [Shared Infrastructure](#shared-infrastructure)
4. [Implementation Steps](#implementation-steps)
5. [File Changes Summary](#file-changes-summary)

---

## Phase 11: Why Am I High/Low Right Now?

### Feature Description

When a user's blood glucose is out of range, a dismissible banner appears at the top of the home screen. Tapping the banner triggers an AI analysis that explains the probable cause of the current glucose state.

### User Flow

```
Home Screen (BG out of range)
         ↓
┌─────────────────────────────────────┐
│ ⚠️ BG is 245 mg/dL     [Analyze] X │  ← Dismissible banner
└─────────────────────────────────────┘
         ↓ tap "Analyze"
┌─────────────────────────────────────┐
│      Why Am I High Right Now?       │
│                                     │
│  Analyzing last 4-6 hours...        │
│  [Loading indicator]                │
│                                     │
└─────────────────────────────────────┘
         ↓
┌─────────────────────────────────────┐
│      Why Am I High Right Now?       │
│                                     │
│  **Probable Cause:**                │
│  You bolused 3.2U for 40g carbs at  │
│  12:30, but your lunch ISF          │
│  historically needs ~15% more       │
│  insulin. Also, your IOB dropped    │
│  faster than expected.              │
│                                     │
│  **Suggestion:**                    │
│  Consider a correction of ~1.5U    │
│                                     │
│  [Close]        [Share PDF]         │
└─────────────────────────────────────┘
```

### Settings (AI Insights > Why High/Low Settings)

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| High Threshold | Decimal | 180 mg/dL | BG above this triggers "Why High" banner |
| Low Threshold | Decimal | 70 mg/dL | BG below this triggers "Why Low" banner |
| Custom Prompt | Text | (default prompt) | Additional instructions for AI analysis |
| Analysis Hours | Picker | 4 hours | How far back to analyze (2, 4, 6 hours) |

### Data Gathered for Analysis

```swift
struct WhyHighLowData {
    // Current State
    let currentBG: Decimal
    let bgTrend: String  // "rising", "falling", "stable"
    let currentIOB: Decimal
    let currentCOB: Int

    // Recent History (configurable: 2-6 hours)
    let glucoseReadings: [GlucoseReading]  // Every reading
    let carbEntries: [CarbEntry]           // All carbs with timestamps
    let bolusEvents: [BolusEvent]          // All boluses
    let tempBasals: [TempBasal]            // All temp basals
    let loopDecisions: [LoopState]         // Algorithm decisions

    // Settings Context
    let currentISF: Decimal
    let currentCR: Decimal
    let currentBasalRate: Decimal

    // Historical Comparison (optional)
    let similarSituations: [HistoricalMatch]?  // Past instances with similar patterns
}
```

### Prompt Template

```
You are analyzing why a person with Type 1 diabetes currently has [high/low] blood glucose.

CURRENT STATE:
- Blood Glucose: {currentBG} mg/dL ({trend})
- IOB (Insulin on Board): {iob}U
- COB (Carbs on Board): {cob}g
- Time: {currentTime}

RECENT HISTORY (Last {hours} hours):
{formattedHistory}

CURRENT SETTINGS:
- ISF: 1U drops BG by {isf} mg/dL
- Carb Ratio: 1U per {cr}g
- Current Basal Rate: {basal}U/hr

{customPrompt}

Please provide:
1. **Probable Cause**: The most likely reason for the current [high/low] BG (be specific)
2. **Contributing Factors**: Any secondary factors that may have contributed
3. **Suggestion**: A conservative, safe recommendation (if appropriate)

Keep the response concise and actionable. Focus on the most likely explanation.
```

### Banner Behavior

- **Appears when**: BG < lowThreshold OR BG > highThreshold
- **Dismissible**: User can tap X to dismiss; banner reappears if BG goes back in range then out again
- **Persistence**: Dismissal state stored in memory (resets on app restart)
- **Animation**: Slide down from top with subtle animation
- **Colors**:
  - High: Orange/red tint
  - Low: Red tint with urgency indicator

### UI Components

```swift
// Banner View
struct WhyHighLowBannerView: View {
    let currentBG: Decimal
    let isHigh: Bool  // true = high, false = low
    let onAnalyze: () -> Void
    let onDismiss: () -> Void
}

// Analysis Sheet
struct WhyHighLowAnalysisView: View {
    @ObservedObject var state: AIInsightsConfig.StateModel
    let isHigh: Bool
}

// Settings View
struct WhyHighLowSettingsView: View {
    @ObservedObject var state: AIInsightsConfig.StateModel
}
```

### UserDefaults Keys

```swift
// Why High/Low Settings
"AIInsightsConfig.whl.highThreshold"      // Decimal, default 180
"AIInsightsConfig.whl.lowThreshold"       // Decimal, default 70
"AIInsightsConfig.whl.analysisHours"      // Int, default 4
"AIInsightsConfig.whl.customPrompt"       // String, default ""
```

---

## Phase 12: Meal Photo Carb Estimation

### Feature Description

Users can take or select a photo of food, optionally add context, and receive an AI-powered carbohydrate estimate with itemized breakdown.

### User Flow

```
Entry Points:
1. Bolus Calculator → Camera icon next to carbs field
2. AI Insights Menu → "Estimate Carbs from Photo"

         ↓
┌─────────────────────────────────────┐
│     Estimate Carbs from Photo       │
│                                     │
│  ┌─────────────────────────────┐   │
│  │                             │   │
│  │      [Photo Preview]        │   │
│  │                             │   │
│  └─────────────────────────────┘   │
│                                     │
│  📷 Take Photo    🖼️ Choose Photo   │
│                                     │
│  Description (optional):            │
│  ┌─────────────────────────────┐   │
│  │ "Small portion, dressing    │   │
│  │  on the side"               │   │
│  └─────────────────────────────┘   │
│                                     │
│  [Estimate Carbs]                   │
└─────────────────────────────────────┘
         ↓
┌─────────────────────────────────────┐
│     Carb Estimate                   │
│                                     │
│  Based on your photo:               │
│                                     │
│  🍝 Pasta (1 cup)         ~35g     │
│  🥖 Garlic bread (2 pcs)  ~20g     │
│  🥗 Side salad            ~5g      │
│  🫒 Dressing (on side)    ~3g      │
│  ─────────────────────────────     │
│  **Total Estimate: ~63g**          │
│                                     │
│  Confidence: Medium-High            │
│  Note: Pasta portion appears        │
│  standard restaurant size           │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ Ask follow-up question...   │   │
│  └─────────────────────────────┘   │
│                                     │
│  [Use 63g]           [Adjust...]   │
└─────────────────────────────────────┘
         ↓ tap "Use 63g"
Returns to Bolus Calculator with carbs = 63
```

### Vision API Integration

Claude's API supports images via base64 encoding:

```swift
// ClaudeAPIService extension for vision
struct ImageContent: Encodable {
    let type = "image"
    let source: ImageSource

    struct ImageSource: Encodable {
        let type = "base64"
        let media_type: String  // "image/jpeg" or "image/png"
        let data: String        // Base64-encoded image data
    }
}

struct ContentBlock: Encodable {
    // Can be either text or image
    let type: String
    let text: String?
    let source: ImageContent.ImageSource?
}

func analyzeImage(
    image: UIImage,
    description: String?,
    customPrompt: String?
) async throws -> String {
    // Resize image for API (max ~1MB recommended)
    // Convert to base64
    // Build message with image + text content
    // Send to Claude API
}
```

### Prompt Template

```
You are a nutrition expert helping someone with Type 1 diabetes estimate carbohydrates in a meal.

Analyze this food photo and estimate the carbohydrate content.

{userDescription != nil ? "User's description: \(userDescription)" : ""}

{customPrompt}

Please provide:
1. **Itemized Breakdown**: List each food item with estimated carbs
   - Use common portion sizes as reference
   - Format: "Food item (portion): ~Xg"

2. **Total Estimate**: Sum of all items (provide a single number, not a range)

3. **Confidence Level**: Low / Medium / High
   - Low: Unclear photo, unusual foods, hard to judge portions
   - Medium: Good photo but some assumptions made
   - High: Clear photo, common foods, obvious portions

4. **Notes**: Any assumptions made or clarifying questions

IMPORTANT:
- Be conservative with estimates when uncertain
- Assume standard portions unless the user indicates otherwise
- If you cannot identify a food, ask for clarification
- Round to nearest 5g for simplicity
```

### Settings (AI Insights > Photo Carb Settings)

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| Custom Prompt | Text | (default) | Additional instructions for estimation |
| Default Portion | Picker | Standard | Assume Small/Standard/Large portions |
| Save Photos | Toggle | Off | Save analyzed photos for reference |

### UI Components

```swift
// Photo Capture/Selection View
struct CarbPhotoPickerView: View {
    @Binding var selectedImage: UIImage?
    @Binding var description: String
    let onAnalyze: () -> Void
}

// Results View
struct CarbEstimateResultView: View {
    let result: CarbEstimateResult
    let onAccept: (Decimal) -> Void
    let onAdjust: () -> Void
    let onAskFollowUp: (String) -> Void
}

// Data Model
struct CarbEstimateResult {
    let items: [CarbItem]
    let totalCarbs: Decimal
    let confidence: ConfidenceLevel
    let notes: String?

    struct CarbItem {
        let name: String
        let portion: String
        let carbs: Decimal
    }

    enum ConfidenceLevel: String {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
    }
}
```

### Integration Points

#### 1. Bolus Calculator (TreatmentsRootView.swift)

```swift
// Add camera button next to carbs field
HStack {
    Text("Carbs")
    Spacer()

    // Existing carb text field
    TextFieldWithToolBar(...)

    // NEW: Camera button
    Button(action: { showCarbPhotoSheet = true }) {
        Image(systemName: "camera.fill")
            .foregroundColor(.blue)
    }
}
.sheet(isPresented: $showCarbPhotoSheet) {
    CarbPhotoEstimateView(
        onAccept: { carbs in
            state.carbs = carbs
            showCarbPhotoSheet = false
        }
    )
}
```

#### 2. AI Insights Menu (AIInsightsConfigRootView.swift)

```swift
// Add new navigation link
NavigationLink(destination: CarbPhotoEstimateView(onAccept: nil)) {
    HStack {
        Image(systemName: "camera.fill")
            .foregroundColor(.mint)
        VStack(alignment: .leading) {
            Text("Estimate Carbs from Photo")
                .font(.headline)
            Text("AI-powered carb counting")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
```

### UserDefaults Keys

```swift
// Photo Carb Settings
"AIInsightsConfig.photo.customPrompt"     // String
"AIInsightsConfig.photo.defaultPortion"   // String: "small", "standard", "large"
"AIInsightsConfig.photo.savePhotos"       // Bool, default false
```

---

## Shared Infrastructure

### 1. AIInsightsConfig.StateModel Extensions

```swift
extension AIInsightsConfig.StateModel {
    // MARK: - Why High/Low
    @Published var whyHighLowResult: String = ""
    @Published var isAnalyzingWhyHighLow: Bool = false
    @Published var whyHighLowError: String?

    // Settings
    @AppStorage("AIInsightsConfig.whl.highThreshold") var whlHighThreshold: Double = 180
    @AppStorage("AIInsightsConfig.whl.lowThreshold") var whlLowThreshold: Double = 70
    @AppStorage("AIInsightsConfig.whl.analysisHours") var whlAnalysisHours: Int = 4
    @AppStorage("AIInsightsConfig.whl.customPrompt") var whlCustomPrompt: String = ""

    // MARK: - Photo Carbs
    @Published var carbEstimateResult: CarbEstimateResult?
    @Published var isEstimatingCarbs: Bool = false
    @Published var carbEstimateError: String?

    // Settings
    @AppStorage("AIInsightsConfig.photo.customPrompt") var photoCustomPrompt: String = ""
    @AppStorage("AIInsightsConfig.photo.defaultPortion") var photoDefaultPortion: String = "standard"

    // MARK: - Methods
    func analyzeWhyHighLow(currentBG: Decimal, isHigh: Bool) async { ... }
    func estimateCarbsFromPhoto(image: UIImage, description: String?) async { ... }
}
```

### 2. ClaudeAPIService Vision Support

```swift
extension ClaudeAPIService {
    func sendMessageWithImage(
        systemPrompt: String,
        userText: String,
        image: UIImage,
        imageDescription: String?
    ) async throws -> String {
        // Resize image to reasonable size (max 1568px on longest side)
        // Convert to JPEG with 0.8 quality
        // Base64 encode
        // Build multi-content message
        // Send to API
    }
}
```

### 3. HealthDataExporter Extension

```swift
extension HealthDataExporter {
    func exportRecentData(hours: Int) -> WhyHighLowData {
        // Focused export for Why High/Low analysis
        // Returns data from last N hours only
    }
}
```

---

## Implementation Steps

### Phase 11: Why Am I High/Low Right Now?

| Step | Description | Files Modified |
|------|-------------|----------------|
| 11.1 | Add settings properties to StateModel | `AIInsightsConfigStateModel.swift` |
| 11.2 | Create WhyHighLowSettingsView | `AIInsightsConfigRootView.swift` |
| 11.3 | Add settings navigation to AI Insights menu | `AIInsightsConfigRootView.swift` |
| 11.4 | Create data export function for recent hours | `HealthDataExporter.swift` |
| 11.5 | Create WhyHighLowAnalysisView sheet | `AIInsightsConfigRootView.swift` |
| 11.6 | Implement analyzeWhyHighLow() method | `AIInsightsConfigStateModel.swift` |
| 11.7 | Create WhyHighLowBannerView component | `WhyHighLowBannerView.swift` (new) |
| 11.8 | Integrate banner into HomeRootView | `HomeRootView.swift` |
| 11.9 | Add banner state management to Home | `HomeStateModel.swift` |
| 11.10 | Test and refine prompts | - |

### Phase 12: Meal Photo Carb Estimation

| Step | Description | Files Modified |
|------|-------------|----------------|
| 12.1 | Add vision support to ClaudeAPIService | `ClaudeAPIService.swift` |
| 12.2 | Add photo carb settings to StateModel | `AIInsightsConfigStateModel.swift` |
| 12.3 | Create CarbEstimateResult data model | `AIInsightsConfigStateModel.swift` |
| 12.4 | Create PhotoCarbSettingsView | `AIInsightsConfigRootView.swift` |
| 12.5 | Create CarbPhotoPickerView | `AIInsightsConfigRootView.swift` |
| 12.6 | Create CarbEstimateResultView | `AIInsightsConfigRootView.swift` |
| 12.7 | Implement estimateCarbsFromPhoto() | `AIInsightsConfigStateModel.swift` |
| 12.8 | Add standalone entry in AI Insights menu | `AIInsightsConfigRootView.swift` |
| 12.9 | Add camera button to TreatmentsRootView | `TreatmentsRootView.swift` |
| 12.10 | Test with various food photos | - |

---

## File Changes Summary

### New Files

| File | Purpose |
|------|---------|
| `Trio/Sources/Modules/Home/View/WhyHighLowBannerView.swift` | Banner component for home screen |

### Modified Files

| File | Changes |
|------|---------|
| `Trio/Sources/Modules/AIInsightsConfig/AIInsightsConfigStateModel.swift` | Add Why High/Low and Photo Carb state, settings, methods |
| `Trio/Sources/Modules/AIInsightsConfig/View/AIInsightsConfigRootView.swift` | Add settings views, analysis views, photo picker, results view |
| `Trio/Sources/Modules/AIInsightsConfig/ClaudeAPIService.swift` | Add vision/image support |
| `Trio/Sources/Modules/AIInsightsConfig/HealthDataExporter.swift` | Add focused recent-hours export |
| `Trio/Sources/Modules/Home/View/HomeRootView.swift` | Integrate Why High/Low banner |
| `Trio/Sources/Modules/Home/HomeStateModel.swift` | Add banner state management |
| `Trio/Sources/Modules/Treatments/View/TreatmentsRootView.swift` | Add camera button for photo carbs |

---

## Safety Considerations

### Why High/Low

- **Never auto-dose**: AI suggestions are informational only
- **Conservative recommendations**: Prompt instructs conservative suggestions
- **Disclaimer**: Include standard "not medical advice" disclaimer
- **No alerts**: This is user-triggered, not automatic notifications

### Photo Carbs

- **User always confirms**: Carbs are NEVER auto-entered
- **Clear UI**: "Use Xg" button requires explicit tap
- **Adjustment option**: User can always modify the estimate
- **Confidence indicator**: Shows how certain the AI is

---

## Testing Plan

### Phase 11 Testing

1. Verify banner appears when BG > high threshold
2. Verify banner appears when BG < low threshold
3. Verify banner dismisses and reappears correctly
4. Test analysis with various scenarios (post-meal high, dawn phenomenon, etc.)
5. Verify settings persist correctly
6. Test custom prompts

### Phase 12 Testing

1. Test camera capture on device
2. Test photo library selection
3. Test with various food types (simple, complex, restaurant)
4. Verify carb value fills correctly in bolus calculator
5. Test follow-up questions
6. Verify settings persist correctly

---

## Document Information

- **Version:** 1.0
- **Created:** December 11, 2025
- **Author:** Claude AI (Implementation Assistant)
- **Status:** Planning Complete - Ready for Implementation
