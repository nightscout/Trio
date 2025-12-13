# Health Metrics Integration for AI Analysis

## Overview

This document describes the implementation of health metrics integration for Claude AI analysis in Trio. The feature enables Trio to read fitness and wellness data from Apple Health (including data synced from wearables like Garmin, Apple Watch, Fitbit, etc.) and include it in AI analysis prompts.

## Goal

Allow users to correlate their glucose patterns with lifestyle factors:
- **Exercise/Activity**: Steps, active calories, exercise minutes
- **Sleep**: Duration, quality, sleep stages (deep, REM, core)
- **Heart Rate**: Resting HR, average HR, min/max HR
- **HRV (Heart Rate Variability)**: SDNN values as stress/recovery indicators
- **Workouts**: Exercise sessions with type, duration, calories burned

## Implementation Status

### Phase 1: Core Infrastructure (COMPLETED)

#### New Files Created:
1. **`Trio/Sources/Models/HealthMetrics.swift`**
   - Data models for all health metric types
   - `DailySteps`, `DailyActivity` - activity tracking
   - `HeartRateReading`, `HRVReading`, `DailyHRVSummary` - heart rate/HRV
   - `SleepSession`, `NightSleepSummary` - sleep tracking
   - `WorkoutSession` - workout data
   - `HealthMetricsSettings` - user preferences for which metrics to include
   - `HealthMetricsExport` - aggregated export model

2. **`Trio/Sources/Services/HealthKit/HealthMetricsService.swift`**
   - Protocol and implementation for fetching health data from Apple Health
   - Methods for fetching steps, activity, heart rate, HRV, sleep, and workouts
   - Async/await implementation using HKStatisticsCollectionQuery and HKSampleQuery
   - Permission request handling

#### Modified Files:
1. **`ServiceAssembly.swift`**
   - Registered `HealthMetricsService` in Swinject dependency injection

2. **`TrioSettings.swift`**
   - Added `healthMetricsSettings: HealthMetricsSettings` property
   - Added decoder support for the new settings

3. **`HealthDataExporter.swift`**
   - Added `healthMetrics` property to `ExportedData`
   - Added `setHealthMetricsService()` method
   - Added `fetchHealthMetrics()` private method
   - Added `formatHealthMetrics()` for Claude prompts
   - Extended `exportData()` with `healthMetricsSettings` parameter
   - Updated Claude-o-Tune, Quick Analysis, and Doctor Visit prompts

4. **`HealthKitStateModel.swift`**
   - Added health metrics toggle state properties
   - Added subscription methods for persisting settings
   - Added permission request on toggle enable

5. **`AppleHealthKitRootView.swift`**
   - Added new UI section for health metrics toggles
   - Toggle for Activity Data (steps, calories, exercise)
   - Toggle for Sleep Data (duration, stages, efficiency)
   - Toggle for Heart Rate & HRV
   - Toggle for Workout Data

## HealthKit Data Types Used

### Read Permissions Required:
```swift
// Activity
HKQuantityType(.stepCount)
HKQuantityType(.activeEnergyBurned)
HKQuantityType(.appleExerciseTime)

// Heart Rate
HKQuantityType(.heartRate)
HKQuantityType(.restingHeartRate)
HKQuantityType(.heartRateVariabilitySDNN)

// Sleep
HKCategoryType(.sleepAnalysis)

// Workouts
HKWorkoutType.workoutType()
```

## AI Prompt Integration

When health metrics are enabled and data is available, the following sections are added to AI analysis prompts:

### Example Output Format:
```
## 🏃 HEALTH & FITNESS METRICS (from Apple Health)

### Daily Activity
• Average Daily Steps: 8,432
• Average Active Calories: 425 kcal
• Average Exercise Minutes: 32 min

Daily Breakdown:
12/01 (Mon): 10,234 steps | 512 kcal | 45 min exercise
12/02 (Tue): 6,821 steps | 328 kcal | 20 min exercise
...

### Sleep Analysis
• Average Sleep Duration: 7.2 hours
• Average Sleep Efficiency: 89%

Nightly Breakdown:
12/01: 22:30-06:45 | 7.5h | Deep: 1.2h | REM: 1.8h
...

### Heart Rate
• Average Resting HR: 58 bpm
• Average HR: 72 bpm
• HR Range: 48-142 bpm

### Heart Rate Variability (HRV)
• Average HRV (SDNN): 45.2 ms

Daily HRV:
12/01: 48.3 ms (range: 32-65)
...

### Workouts
• Total Workouts: 5
• Total Workout Time: 185 min
• Total Workout Calories: 1,240 kcal

By Type:
• Running: 3x, 120 min total
• Cycling: 2x, 65 min total

Recent Workouts:
12/01 08:30: Running | 45 min | 420 kcal | Avg HR: 145
...
```

## Claude Analysis Instructions

When health metrics are included, Claude is prompted to analyze:

1. **Exercise Impact**: How workouts and daily activity affect glucose control
2. **Sleep Quality**: Patterns between sleep duration/quality and next-day glucose stability
3. **HRV Trends**: Whether HRV (stress/recovery indicator) correlates with insulin sensitivity
4. **Activity Patterns**: Glucose differences on high vs low activity days

## User Flow

1. User goes to **Settings > Apple Health**
2. Enables "Connect to Apple Health" (existing toggle)
3. New section appears: **"Health Metrics for AI Analysis"**
4. User enables desired data types:
   - Activity Data
   - Sleep Data
   - Heart Rate & HRV
   - Workout Data
5. iOS prompts for HealthKit read permissions
6. When using Claude-o-Tune, Quick Analysis, or Doctor Visit, health data is automatically included

## Future Enhancements (Not Yet Implemented)

### Phase 2: Advanced Correlation Analysis
- Pre-computed correlations between activity and glucose
- Sleep score impact on insulin sensitivity
- Exercise timing recommendations

### Phase 3: Predictive Features
- Predict glucose impact based on planned workouts
- Suggest pre-workout carbs based on historical patterns
- Alert for unusual HRV + glucose patterns

### Phase 4: Visualization
- Activity/glucose overlay charts
- Sleep quality vs TIR trends
- Workout impact timeline view

## Technical Notes

### Garmin Data Flow
Garmin Connect syncs to Apple Health automatically. The data flow is:
```
Garmin Watch → Garmin Connect App → Apple Health → Trio (via HealthKit)
```

### Data Freshness
- Activity data: Updated throughout the day
- Sleep data: Available after wake-up (usually by 9-10 AM)
- HRV: Updated with each heart rate sample
- Workouts: Available immediately after sync

### Privacy
- All health data stays on device
- Only included in prompts when user explicitly enables toggles
- Data is formatted as text, not raw values sent to API
