import SwiftUI

/// A dismissible banner that appears when glucose is out of range
/// Provides quick access to AI analysis of why glucose might be high or low
struct WhyHighLowBannerView: View {
    let currentBG: Decimal
    let bgTrend: String
    let currentIOB: Decimal
    let currentCOB: Int
    let isHigh: Bool // true = high, false = low
    let units: String
    let onAnalyze: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: isHigh ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.title2)
                .foregroundColor(.white)

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(isHigh ? "Blood Glucose is High" : "Blood Glucose is Low")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("\(NSDecimalNumber(decimal: currentBG).intValue) \(units)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
            }

            Spacer()

            // Analyze button
            Button(action: onAnalyze) {
                Text("Analyze")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.25))
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }

            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                gradient: Gradient(colors: isHigh ? [.orange, .red.opacity(0.8)] : [.red, .red.opacity(0.8)]),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(12)
        .shadow(color: (isHigh ? Color.orange : Color.red).opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

#Preview("High BG Banner") {
    VStack {
        WhyHighLowBannerView(
            currentBG: 245,
            bgTrend: "rising",
            currentIOB: 2.5,
            currentCOB: 15,
            isHigh: true,
            units: "mg/dL",
            onAnalyze: {},
            onDismiss: {}
        )
        .padding()

        Spacer()
    }
    .background(Color.gray.opacity(0.2))
}

#Preview("Low BG Banner") {
    VStack {
        WhyHighLowBannerView(
            currentBG: 62,
            bgTrend: "falling",
            currentIOB: 1.2,
            currentCOB: 0,
            isHigh: false,
            units: "mg/dL",
            onAnalyze: {},
            onDismiss: {}
        )
        .padding()

        Spacer()
    }
    .background(Color.gray.opacity(0.2))
}
