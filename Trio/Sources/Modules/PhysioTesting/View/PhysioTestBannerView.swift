import SwiftUI

extension PhysioTesting {
    struct BannerView: View {
        let testType: TestType
        let phase: TestPhase
        let elapsedMinutes: Int
        let currentGlucose: Double
        let baselineGlucose: Double
        let onStop: () -> Void

        var body: some View {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.orange)
                    .clipShape(Circle())

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text("Physio Test: \(testType.displayName)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    HStack(spacing: 8) {
                        Text(phase.displayName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("\(elapsedMinutes) min")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(.orange)
                    }
                }

                Spacer()

                // Stop button
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.red)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(0.4), lineWidth: 1)
            )
        }
    }
}
