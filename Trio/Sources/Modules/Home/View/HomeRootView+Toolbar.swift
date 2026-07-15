import SwiftUI
import UIKit

// MARK: - Toolbar: conditional warning items (notifications off, pump timezone)

extension Home.RootView {
    @ViewBuilder func pumpTimezoneView(_ badgeImage: UIImage, _ badgeColor: Color) -> some View {
        HStack {
            Image(uiImage: badgeImage.withRenderingMode(.alwaysTemplate))
                .font(.system(size: 14))
                .colorMultiply(badgeColor)
            Text(String(localized: "Time Change Detected", comment: ""))
                .bold()
                .font(.system(size: 14))
                .foregroundStyle(badgeColor)
        }
        .onTapGesture {
            if state.pumpDisplayState != nil {
                // sends user to pump settings
                state.shouldDisplayPumpSetupSheet.toggle()
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .overlay(
            Capsule()
                .stroke(badgeColor.opacity(0.4), lineWidth: 2)
        )
    }

    @ViewBuilder func alertSafetyNotificationsView(geo: GeometryProxy) -> some View {
        ZStack {
            /// rectangle as background
            RoundedRectangle(cornerRadius: 15)
                .fill(
                    Color(
                        red: 0.9,
                        green: 0.133333333,
                        blue: 0.2156862745
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .frame(height: geo.size.height * 0.08)
                .coordinateSpace(name: "alertSafetyNotificationsView")
                .shadow(
                    color: colorScheme == .dark ? Color(red: 0.02745098039, green: 0.1098039216, blue: 0.1411764706) :
                        Color.black.opacity(0.33),
                    radius: 3
                )
            HStack {
                Spacer()
                VStack {
                    Text("⚠️ Safety Notifications are OFF")
                        .font(.headline)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .foregroundStyle(.white.gradient)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Fix now by turning Notifications ON.")
                        .font(.footnote)
                        .fontDesign(.rounded)
                        .foregroundStyle(.white.gradient)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.leading, 5)
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.white)
                    .font(.headline)
            }.padding(.horizontal, 10)
                .padding(.trailing, 8)
                .onTapGesture {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                }
        }.padding(.horizontal, 10)
            .padding(.top, 0)
    }
}
