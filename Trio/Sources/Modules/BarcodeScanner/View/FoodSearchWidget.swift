import SwiftUI

extension BarcodeScanner {
    /// A combined component that provides a search field, result list, and loading state for food searches.
    struct FoodSearchWidget<Leading: View, Trailing: View>: View {
        @Binding var searchText: String
        var isFocused: FocusState<Bool>.Binding
        var isSearching: Bool
        var searchError: String?
        var searchResults: [FoodItem]
        var hasMoreSearchResults: Bool
        var isLoadingMoreSearchResults: Bool
        var onSubmit: () -> Void
        var onClear: () -> Void
        var onChange: () -> Void
        var onItemAdd: (FoodItem) -> Void
        var onLoadMore: () -> Void

        @ViewBuilder let leadingSearchContent: Leading
        @ViewBuilder let trailingSearchContent: Trailing

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    leadingSearchContent
                    ProductSearchField(
                        searchText: $searchText,
                        isFocused: isFocused,
                        onSubmit: onSubmit,
                        onClear: onClear,
                        onChange: onChange
                    )
                    trailingSearchContent
                }

                if isSearching {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 8)
                        Spacer()
                    }
                } else if let error = searchError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if !searchResults.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(searchResults) { item in
                            FoodSearchResultRow(item: item, onAdd: { onItemAdd(item) })
                            if item.id != searchResults.last?.id {
                                Divider().opacity(0.3)
                            }
                        }

                        if hasMoreSearchResults {
                            Button(action: onLoadMore) {
                                HStack {
                                    if isLoadingMoreSearchResults {
                                        ProgressView()
                                            .scaleEffect(0.9)
                                    } else {
                                        Text("Show 4 more results")
                                            .font(.caption.weight(.medium))
                                        Image(systemName: "chevron.down")
                                            .font(.caption)
                                    }
                                }
                                .foregroundStyle(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoadingMoreSearchResults)
                        }
                    }
                }
            }
        }
    }
}

extension BarcodeScanner.FoodSearchWidget where Leading == EmptyView, Trailing == EmptyView {
    init(
        searchText: Binding<String>,
        isFocused: FocusState<Bool>.Binding,
        isSearching: Bool,
        searchError: String?,
        searchResults: [FoodItem],
        hasMoreSearchResults: Bool,
        isLoadingMoreSearchResults: Bool,
        onSubmit: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onChange: @escaping () -> Void,
        onItemAdd: @escaping (FoodItem) -> Void,
        onLoadMore: @escaping () -> Void
    ) {
        _searchText = searchText
        self.isFocused = isFocused
        self.isSearching = isSearching
        self.searchError = searchError
        self.searchResults = searchResults
        self.hasMoreSearchResults = hasMoreSearchResults
        self.isLoadingMoreSearchResults = isLoadingMoreSearchResults
        self.onSubmit = onSubmit
        self.onClear = onClear
        self.onChange = onChange
        self.onItemAdd = onItemAdd
        self.onLoadMore = onLoadMore
        leadingSearchContent = EmptyView()
        trailingSearchContent = EmptyView()
    }
}

extension BarcodeScanner {
    /// A reusable search text field component
    struct ProductSearchField: View {
        @Binding var searchText: String
        var isFocused: FocusState<Bool>.Binding
        var onSubmit: () -> Void
        var onClear: () -> Void
        var onChange: () -> Void

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Search foods..."), text: $searchText)
                    .focused(isFocused)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit(onSubmit)
                    .toolbar {
                        if isFocused.wrappedValue {
                            ToolbarItemGroup(placement: .keyboard) {
                                Button(action: {
                                    searchText = ""
                                }) {
                                    Image(systemName: "trash")
                                }
                                Spacer()
                                Button(action: {
                                    isFocused.wrappedValue = false
                                }) {
                                    Image(systemName: "keyboard.chevron.compact.down")
                                }
                            }
                        }
                    }
                    .onChange(of: searchText) { _, _ in
                        onChange()
                    }

                if !searchText.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    /// A compact row view for displaying food search results
    struct FoodSearchResultRow: View {
        let item: FoodItem
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
