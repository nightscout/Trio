import SwiftUI

struct SettingsRowView: View {
    let imageName: String
    let title: String
    let tint: Color
    let spacing: CGFloat?
    let font: CGFloat?

    init(imageName: String, title: String, tint: Color, spacing: CGFloat? = 12, font: CGFloat? = 35) {
        self.imageName = imageName
        self.title = title
        self.tint = tint
        self.spacing = spacing
        self.font = font
    }

    var body: some View {
        HStack(spacing: spacing ?? 12, content: {
            Image(systemName: imageName)
                .imageScale(.small)
                .font(.system(size: font ?? 35))
                .foregroundColor(tint)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
        })
    }
}

struct SettingsRowViewCustomImage: View {
    let imageName: String
    let title: String
    let frame: CGFloat?
    let spacing: CGFloat?

    init(imageName: String, title: String, frame: CGFloat? = 35, spacing: CGFloat? = 12) {
        self.imageName = imageName
        self.title = title
        self.frame = frame
        self.spacing = spacing
    }

    var body: some View {
        HStack(spacing: spacing ?? 12, content: {
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: frame ?? 35, height: frame ?? 35)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
        })
    }
}
