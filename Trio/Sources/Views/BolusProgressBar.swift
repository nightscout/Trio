import SwiftUI

struct BolusProgressBar: View {
    let progress: Decimal

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 15)
                .frame(height: 6)
                .foregroundColor(.clear)
                .background(
                    LinearGradient(colors: [
                        Color(red: 0.7215686275, green: 0.3411764706, blue: 1),
                        Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569),
                        Color(red: 0.4862745098, green: 0.5450980392, blue: 0.9529411765),
                        Color(red: 0.3411764706, green: 0.6666666667, blue: 0.9254901961),
                        Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902)
                    ], startPoint: .leading, endPoint: .trailing)
                        .mask(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 15)
                                .frame(width: geo.size.width * CGFloat(progress))
                        }
                )
        }
        .frame(height: 6)
    }
}
