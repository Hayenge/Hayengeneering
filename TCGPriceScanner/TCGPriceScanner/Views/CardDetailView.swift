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

                // Card header
                cardHeader

                // Price guide summary
                priceGuideSummary

                // Marketplace listings
                listingsSection
            }
            .padding()
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let url = card.cardMarketURL {
                    Button {
                        openURL(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                }
            }
        }
        .task {
            viewModel.loadPrices()
        }
    }

    // MARK: - Card Header

    private var cardHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            // Card image
            AsyncImage(url: card.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure, .empty:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(card.game.accentColor.opacity(0.2))
                        .overlay(
                            Text(card.game.icon)
                                .font(.largeTitle)
                        )
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

                // Trend price chip
                if let trend = viewModel.priceGuide?.trend {
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trend")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(trend.priceString())
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
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

    // MARK: - Price Guide Summary

    @ViewBuilder
    private var priceGuideSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Price Overview")
                .font(.headline)

            switch viewModel.priceState {
            case .loading:
                HStack {
                    ProgressView()
                    Text("Loading prices…")
                        .foregroundColor(.secondary)
                }

            case .loaded(let guide, _), .error where viewModel.priceGuide != nil:
                let g = viewModel.priceGuide ?? guide
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    PriceTileView(label: "Low", value: g.low, color: .green)
                    PriceTileView(label: "Mid", value: g.mid, color: .blue)
                    PriceTileView(label: "High", value: g.high, color: .orange)
                    PriceTileView(label: "Trend", value: g.trend, color: .purple)
                    PriceTileView(label: "Avg (7d)", value: g.avg7, color: .teal)
                    PriceTileView(label: "Avg (30d)", value: g.avg30, color: .indigo)
                }

                if let lowFoil = g.lowFoil {
                    Divider()
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.yellow)
                        Text("Foil Low: \(lowFoil.priceString())")
                            .font(.subheadline)
                        Spacer()
                        if let trendFoil = g.trendFoil {
                            Text("Foil Trend: \(trendFoil.priceString())")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }

            case .error(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    Button("Retry") { viewModel.refresh() }
                        .font(.caption)
                }

            case .idle:
                EmptyView()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    // MARK: - Listings Section

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

            // Filters
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
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    private var listingFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Sort picker
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

            // Condition filter
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

            // Foil toggle
            Toggle("Foil only", isOn: $viewModel.showFoilOnly)
                .font(.caption)
                .tint(.yellow)
        }
    }
}

// MARK: - Price Tile

struct PriceTileView: View {
    let label: String
    let value: Double?
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            if let value {
                Text(value.priceString())
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
                .foregroundColor(.primary)
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
        case .mintMint, .nearMint: return .green
        case .excellentMinus:      return .teal
        case .goodPlus, .good:     return .blue
        case .poorlyPlayed:        return .orange
        case .poor:                return .red
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
