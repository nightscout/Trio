import Foundation

// MARK: - Garmin Firebase Configuration

// This file holds the Firebase project configuration for the user's Garmin Firestore database.
// Values are injected at build time by GitHub Actions from repository secrets.
//
// To configure: Add these GitHub secrets to your repository:
//   GARMIN_FIREBASE_API_KEY          - Firebase Web API Key
//   GARMIN_FIREBASE_PROJECT_ID       - Firebase Project ID
//   GARMIN_FIREBASE_GCM_SENDER_ID    - GCM Sender ID (number)
//   GARMIN_FIREBASE_GOOGLE_APP_ID    - Google App ID (1:xxxxx:ios:xxxxx)
//   GARMIN_FIREBASE_STORAGE_BUCKET   - Firebase Storage Bucket
//   GARMIN_FIREBASE_USER_ID          - Your Firestore user UID
//   GARMIN_FIREBASE_EMAIL            - Firebase Auth email
//   GARMIN_FIREBASE_PASSWORD         - Firebase Auth password
//
// The build workflow replaces the placeholder values below before compilation.
// If secrets are not configured, Garmin Firestore integration is gracefully disabled.

enum GarminFirebaseConstants {
    // Firebase project config — replaced at build time by GitHub Actions
    static let apiKey = "__GARMIN_FIREBASE_API_KEY__"
    static let projectID = "__GARMIN_FIREBASE_PROJECT_ID__"
    static let gcmSenderID = "__GARMIN_FIREBASE_GCM_SENDER_ID__"
    static let googleAppID = "__GARMIN_FIREBASE_GOOGLE_APP_ID__"
    static let storageBucket = "__GARMIN_FIREBASE_STORAGE_BUCKET__"

    // Firestore user identity
    static let firestoreUserID = "__GARMIN_FIREBASE_USER_ID__"

    // Firebase Auth credentials (email/password)
    static let authEmail = "__GARMIN_FIREBASE_EMAIL__"
    static let authPassword = "__GARMIN_FIREBASE_PASSWORD__"

    /// Returns true if the build-time secrets were injected (i.e., not still placeholder values).
    static var isConfigured: Bool {
        !apiKey.hasPrefix("__") && !projectID.hasPrefix("__") && !googleAppID.hasPrefix("__")
    }
}
