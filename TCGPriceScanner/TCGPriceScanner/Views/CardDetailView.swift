import SwiftUI

struct CardDetailView: View {
    let card: Card
    @StateObject private var viewModel: CardPriceViewModel
    @Environment(\.openURL) private var openURL

    init(card: Card) {
        self.card = card
        _viewModel = StateObject(wrappedValue: CardPriceViewModel(card: card))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                cardHeader
                priceSourceFilter
                tcgPlayerSection
                priceChartingSection
                listingsSection
            }
            .padding()
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                externalLinksMenu
            }
        }
        .task {
            viewModel.loadPrices()
        }
    }

    // MARK: - External Links Menu

    @ViewBuilder
    private var externalLinksMenu: some View {
        Menu {
            if let url = viewModel.tcgPlayerPrice?.url {
                Button {
                    openURL(url)
                } label: {
                    Label("View on TCGPlayer", systemImage: "arrow.up.right.square")
                }
            }
            if let url = viewModel.priceChartingPrice?.url {
                Button {
                    openURL(url)
                } label: {
                    Label("View on PriceCharting", systemImage: "arrow.up.right.square")
                }
            }
            if let url = card.cardMarketURL {
                Button {
                    openURL(url)
                } label: {
                    Label("View on CardMarket", systemImage: "arrow.up.right.square")
                }
            }
        } label: {
            Image(systemName: "arrow.up.right.square")
        }
    }

    // MARK: - Card Header

    private var cardHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: card.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure, .empty:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(card.game.accentColor.opacity(0.2))
                        .overlay(Text(card.game.icon).font(.largeTitle))
                @unknown default:
                    ProgressView()
                }
            }
            .frame(width: 120, height: 168)
            .cornerRadius(8)
            .shadow(radius: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(card.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(2)

                HStack {
                    Text(card.game.icon)
                    Text(card.game.rawValue)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let expansion = card.expansionName {
                    Label(expansion, systemImage: "folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let number = card.cardNumber {
                    Label("# \(number)", systemImage: "number")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let rarity = card.rarity {
                    Text(rarity)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(card.game.accentColor.opacity(0.2), in: Capsule())
                        .foregroundColor(card.game.accentColor)
                }

                // Best available market price chip
                if let market = viewModel.tcgPlayerPrice?.marketPrice {
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Market (TCGPlayer)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(market.usdString())
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                } else if let loose = viewModel.priceChartingPrice?.loosePrice {
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ungraded (PriceCharting)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(loose.usdString())
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                }
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    // MARK: - Price Source Filter

    private var priceSourceFilter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Price Sources")
                .font(.headline)

            HStack(spacing: 10) {
                PriceSourceChip(
                    title: "TCGPlayer",
                    systemImage: "dollarsign.circle.fill",
                    color: .blue,
                    isSelected: $viewModel.showTCGPlayerPrices
                )
                PriceSourceChip(
                    title: "PriceCharting",
                    systemImage: "chart.line.uptrend.xyaxis.circle.fill",
                    color: .green,
                    isSelected: $viewModel.showPriceChartingPrices
                )
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    // MARK: - TCGPlayer Section

    @ViewBuilder
    private var tcgPlayerSection: some View {
        if viewModel.showTCGPlayerPrices {
            VStack(alignment: .leading, spacing: 12) {
                // Source header
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundColor(.blue)
                    Text("TCGPlayer")
                        .font(.headline)
                    Spacer()
                    if case .loading = viewModel.tcgPlayerState {
                        ProgressView().scaleEffect(0.7)
                    }
                }

                switch viewModel.tcgPlayerState {
                case .loading:
                    HStack {
                        ProgressView()
                        Text("Fetching TCGPlayer prices…")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }

                case .loaded:
                    if let price = viewModel.tcgPlayerPrice {
                        tcgPlayerPriceGrid(price)
                    }

                case .notFound:
                    Label("Card not found on TCGPlayer.", systemImage: "magnifyingglass")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                case .notConfigured:
                    notConfiguredBanner(
                        message: "Add your TCGPlayer API credentials in TCGPlayerConfig to see live prices.",
                        color: .blue
                    )

                case .unavailable:
                    Label("\(card.game.rawValue) is not available on TCGPlayer.", systemImage: "xmark.circle")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                case .error(let msg):
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundColor(.orange)

                case .idle:
                    EmptyView()
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        }
    }

    @ViewBuilder
    private func tcgPlayerPriceGrid(_ price: TCGPlayerPrice) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
        ) {
            PriceTileView(label: "Market",     value: price.marketPrice,    color: .blue,   currency: "$")
            PriceTileView(label: "Low",        value: price.lowPrice,       color: .green,  currency: "$")
            PriceTileView(label: "Mid",        value: price.midPrice,       color: .teal,   currency: "$")
            PriceTileView(label: "High",       value: price.highPrice,      color: .orange, currency: "$")
            PriceTileView(label: "Direct Low", value: price.directLowPrice, color: .indigo, currency: "$")
        }

        if let foilMarket = price.foilMarketPrice {
            Divider()
            HStack {
                Image(systemName: "sparkles").foregroundColor(.yellow)
                Text("Foil Market: \(foilMarket.usdString())")
                    .font(.subheadline)
                Spacer()
                if let foilLow = price.foilLowPrice {
                    Text("Foil Low: \(foilLow.usdString())")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - PriceCharting Section

    @ViewBuilder
    private var priceChartingSection: some View {
        if viewModel.showPriceChartingPrices {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                        .foregroundColor(.green)
                    Text("PriceCharting")
                        .font(.headline)
                    Spacer()
                    if case .loading = viewModel.priceChartingState {
                        ProgressView().scaleEffect(0.7)
                    }
                }

                switch viewModel.priceChartingState {
                case .loading:
                    HStack {
                        ProgressView()
                        Text("Fetching PriceCharting prices…")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }

                case .loaded:
                    if let price = viewModel.priceChartingPrice {
                        priceChartingPriceGrid(price)
                    }

                case .notFound:
                    Label("Card not found on PriceCharting.", systemImage: "magnifyingglass")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                case .notConfigured:
                    notConfiguredBanner(
                        message: "Add your PriceCharting API key in PriceChartingConfig to see live prices.",
                        color: .green
                    )

                case .unavailable:
                    Label("\(card.game.rawValue) is not available on PriceCharting.", systemImage: "xmark.circle")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                case .error(let msg):
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundColor(.orange)

                case .idle:
                    EmptyView()
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        }
    }

    @ViewBuilder
    private func priceChartingPriceGrid(_ price: PriceChartingPrice) -> some View {
        if let name = price.consoleName {
            Text(name.capitalized)
                .font(.caption)
                .foregroundColor(.secondary)
        }

        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
        ) {
            PriceTileView(label: "Ungraded",  value: price.loosePrice,    color: .green,  currency: "$")
            PriceTileView(label: "Graded",    value: price.gradedPrice,   color: .purple, currency: "$")
            PriceTileView(label: "New/Sealed",value: price.newPrice,      color: .blue,   currency: "$")
        }
    }

    // MARK: - Not Configured Banner

    private func notConfiguredBanner(message: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "key.fill")
                .foregroundColor(color)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Marketplace Listings (CardMarket backend)

    @ViewBuilder
    private var listingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Marketplace Listings")
                    .font(.headline)
                Spacer()
                if !viewModel.articles.isEmpty {
                    Text("\(viewModel.availableListings) listings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !viewModel.articles.isEmpty {
                listingFilters
            }

            if case .loading = viewModel.priceState {
                HStack { ProgressView(); Spacer() }
            } else if viewModel.filteredArticles.isEmpty && !viewModel.articles.isEmpty {
                Text("No listings match your filters.")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(viewModel.filteredArticles) { article in
                    ArticleRowView(article: article)
                    Divider()
                }
            }

            if viewModel.articles.isEmpty, case .loaded = viewModel.priceState {
                Text("No marketplace listings available.")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }

            if case .error(let msg) = viewModel.priceState {
                if viewModel.articles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(msg, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                        Button("Retry") { viewModel.refresh() }
                            .font(.caption)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    private var listingFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sort:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Sort", selection: $viewModel.sortOrder) {
                    ForEach(CardPriceViewModel.SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "All", isSelected: viewModel.selectedConditionFilter == nil) {
                        viewModel.selectedConditionFilter = nil
                    }
                    ForEach(CardCondition.allCases, id: \.self) { condition in
                        FilterChip(title: condition.shortName, isSelected: viewModel.selectedConditionFilter == condition) {
                            viewModel.selectedConditionFilter =
                                viewModel.selectedConditionFilter == condition ? nil : condition
                        }
                    }
                }
            }

            Toggle("Foil only", isOn: $viewModel.showFoilOnly)
                .font(.caption)
                .tint(.yellow)
        }
    }
}

// MARK: - Price Source Chip

struct PriceSourceChip: View {
    let title: String
    let systemImage: String
    let color: Color
    @Binding var isSelected: Bool

    var body: some View {
        Button {
            isSelected.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? color : Color(.systemGray5), in: Capsule())
            .foregroundColor(isSelected ? .white : .secondary)
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Price Tile

struct PriceTileView: View {
    let label: String
    let value: Double?
    let color: Color
    var currency: String = "€"

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            if let value {
                Text(currency == "$" ? value.usdString() : value.priceString())
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
            } else {
                Text("—")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Article Row

struct ArticleRowView: View {
    let article: CardArticle

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(article.seller.username)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let country = article.seller.country {
                        Text(countryFlag(country))
                            .font(.caption)
                    }
                    if let rating = article.seller.avgRating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", rating))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                HStack(spacing: 8) {
                    conditionBadge
                    if article.isFoil {
                        Text("✨ Foil")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                    if article.isPlayset {
                        Text("4x Playset")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    if article.count > 1 {
                        Text("×\(article.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Text(article.price.priceString())
                .font(.headline)
                .fontWeight(.bold)
        }
        .padding(.vertical, 4)
    }

    private var conditionBadge: some View {
        Text(article.condition.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(conditionColor(article.condition).opacity(0.15), in: Capsule())
            .foregroundColor(conditionColor(article.condition))
    }

    private func conditionColor(_ condition: CardCondition) -> Color {
        switch condition {
        case .mintMint, .nearMint:  return .green
        case .excellentMinus:       return .teal
        case .goodPlus, .good:      return .blue
        case .poorlyPlayed:         return .orange
        case .poor:                 return .red
        }
    }

    private func countryFlag(_ code: String) -> String {
        let base: UInt32 = 127397
        var flag = ""
        for scalar in code.uppercased().unicodeScalars {
            if let s = Unicode.Scalar(base + scalar.value) {
                flag.append(Character(s))
            }
        }
        return flag
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color(.systemGray5), in: Capsule())
                .foregroundColor(isSelected ? .white : .primary)
        }
    }
}
