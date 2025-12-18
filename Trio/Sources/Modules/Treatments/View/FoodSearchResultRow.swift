import SwiftUI

extension Treatments {
    /// A compact row view for displaying food search results
    struct FoodSearchResultRow: View {
        let item: BarcodeScanner.FoodItem
        let onAdd: () -> Void

        var body: some View {
            Button(action: onAdd) {
                HStack(spacing: 12) {
                    // Product image
                    productImage
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Product info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            if let brand = item.brand {
                                Text(brand)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if let carbs = item.nutriments.carbohydratesPer100g {
                                Text("\(carbs, specifier: "%.1f")g carbs/100g")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }

                    Spacer()

                    // Add button indicator
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }

        @ViewBuilder private var productImage: some View {
            switch item.imageSource {
            case let .url(url):
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        imagePlaceholder
                    default:
                        ProgressView()
                            .frame(width: 44, height: 44)
                    }
                }

            case let .image(uiImage):
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()

            case .none:
                imagePlaceholder
            }
        }

        private var imagePlaceholder: some View {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.2))
                .overlay(
                    Image(systemName: "fork.knife")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                )
        }
    }
}
