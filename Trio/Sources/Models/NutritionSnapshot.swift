// This file previously contained NutritionSnapshot, InferredMealEvent, and
// NutritionSnapshotStore — the cumulative-snapshot-delta meal detection system.
//
// That approach has been replaced by direct sample-based detection in
// NutritionHealthService, which queries individual HealthKit samples, groups
// them by their creationDate within a 15-minute window, and publishes
// DetectedMeal objects directly. No snapshots, no deltas.
//
// The old nutrition_snapshots.json file on disk can be safely ignored/deleted.
