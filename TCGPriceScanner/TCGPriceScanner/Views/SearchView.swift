import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var selectedGame: TCGGame = .magicTheGathering
    @State private var isSearching = false
    @State private var results: [Card] = []
    @State private var errorMessage: String? = nil
    @FocusState private var isTextFieldFocused: Bool

    private let apiService = CardMarketService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Game picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(TCGGame.allCases) { game in
                            GameChip(game: game, isSelected: selectedGame == game) {
                                selectedGame = game
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemGroupedBackground))

                Divider()

                // Results
                Group {
                    if isSearching {
                        Spacer()
                        ProgressView("Searching CardMarket…")
                        Spacer()
                    } else if let error = errorMessage {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.orange)
                            Text(error)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        }
                        Spacer()
                    } else if results.isEmpty && !query.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No results found")
                                .font(.headline)
                            Text("Try a different card name or game.")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                        Spacer()
                    } else if results.isEmpty {
                        emptyState
                    } else {
                        List(results) { card in
                            NavigationLink(destination: CardDetailView(card: card)) {
                                CardSearchRowView(card: card)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Card name…")
            .onSubmit(of: .search) {
                performSearch()
            }
            .onChange(of: selectedGame) { _, _ in
                if !query.isEmpty { performSearch() }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "creditcard.viewfinder")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            Text("Search any TCG Card")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Search across all popular TCGs and get live prices from CardMarket.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)

            // Popular searches
            VStack(alignment: .leading, spacing: 8) {
                Text("Popular searches")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(popularSearches, id: \.self) { term in
                            Button(term) {
                                query = term
                                performSearch()
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            Spacer()
        }
    }

    private var popularSearches: [String] {
        switch selectedGame {
        case .magicTheGathering: return ["Black Lotus", "Lightning Bolt", "Counterspell", "Force of Will"]
        case .pokemon:           return ["Charizard", "Pikachu", "Mewtwo", "Umbreon"]
        case .yugioh:            return ["Blue-Eyes White Dragon", "Dark Magician", "Exodia", "Pot of Greed"]
        case .lorcana:           return ["Elsa", "Mickey Mouse", "Moana", "Stitch"]
        case .onePiece:          return ["Monkey D. Luffy", "Roronoa Zoro", "Nami", "Trafalgar Law"]
        case .starWarsUnlimited: return ["Luke Skywalker", "Darth Vader", "Han Solo", "Yoda"]
        default:                 return ["Search for your favourite card"]
        }
    }

    // MARK: - Search

    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSearching = true
        errorMessage = nil
        results = []

        Task {
            do {
                results = try await apiService.searchCards(name: trimmed, game: selectedGame)
                if results.isEmpty {
                    errorMessage = nil
                }
            } catch CardMarketError.notConfigured {
                errorMessage = "CardMarket API not configured.\nAdd your credentials in CardMarketConfig.swift."
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }
}

// MARK: - Game Chip

struct GameChip: View {
    let game: TCGGame
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(game.icon)
                    .font(.subheadline)
                Text(game.rawValue)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected ? game.accentColor : Color(.systemGray5),
                in: Capsule()
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Card Search Row

struct CardSearchRowView: View {
    let card: Card

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            AsyncImage(url: card.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                default:
                    RoundedRectangle(cornerRadius: 4)
                        .fill(card.game.accentColor.opacity(0.15))
                        .overlay(Text(card.game.icon))
                }
            }
            .frame(width: 44, height: 62)
            .cornerRadius(4)

            VStack(alignment: .leading, spacing: 3) {
                Text(card.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let expansion = card.expansionName {
                    Text(expansion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(card.game.icon)
                    if let rarity = card.rarity {
                        Text(rarity)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(card.game.accentColor.opacity(0.15), in: Capsule())
                            .foregroundColor(card.game.accentColor)
                    }
                }
            }

            Spacer()

            // Price hint from search result
            if let trend = card.priceGuide?.trend {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(trend.priceString())
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("trend")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if let low = card.priceGuide?.low {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(low.priceString())
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                    Text("from")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
