import SwiftUI

/// Shown where a screen's stored values are overridden by the active dosing mode.
struct DosingModeOverrideNote: View {
    let mode: DosingMode
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: mode.icon)
            Text("\(mode.displayName) is on. \(message)")
        }
        .font(.footnote)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
