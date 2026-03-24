import SwiftUI
import Combine

// MARK: - Price View State

enum PriceState {
    case idle
    case loading
    case loaded(PriceGuide, [CardArticle])
    case error(String)
}

// MARK: - Card Price ViewModel

@MainActor
final class CardPriceViewModel: ObservableObject {

    @Published var priceState: PriceState = .idle
    @Published var articles: [CardArticle] = []
    @Published var priceGuide: PriceGuide?
    @Published var selectedConditionFilter: CardCondition? = nil
    @Published var showFoilOnly: Bool = false
    @Published var sortOrder: SortOrder = .priceAscending

    private let apiService = CardMarketService.shared
    let card: Card

    enum SortOrder: String, CaseIterable {
        case priceAscending = "Price: Low to High"
        case priceDescending = "Price: High to Low"
        case conditionBest = "Best Condition First"
        case sellerRating = "Seller Rating"
    }

    init(card: Card) {
        self.card = card
        // Use cached price guide from search result if available
        if let cached = card.priceGuide {
            priceGuide = cached
        }
    }

    // MARK: - Data Loading

    func loadPrices() {
        guard case .idle = priceState else { return }
        priceState = .loading

        Task {
            do {
                async let guideTask = apiService.getPriceGuide(productId: card.id)
                async let articlesTask = apiService.getArticles(productId: card.id, maxResults: 50)

                let (guide, fetchedArticles) = try await (guideTask, articlesTask)
                priceGuide = guide
                articles = fetchedArticles
                priceState = .loaded(guide, fetchedArticles)
            } catch CardMarketError.notConfigured {
                // Show cached price guide if available, with a notice
                if let cached = card.priceGuide {
                    priceState = .loaded(cached, [])
                } else {
                    priceState = .error("Add your CardMarket API credentials to see live prices.")
                }
            } catch {
                priceState = .error(error.localizedDescription)
            }
        }
    }

    func refresh() {
        priceState = .idle
        articles = []
        loadPrices()
    }

    // MARK: - Filtered / Sorted Articles

    var filteredArticles: [CardArticle] {
        var result = articles

        if let condition = selectedConditionFilter {
            result = result.filter { $0.condition == condition }
        }

        if showFoilOnly {
            result = result.filter { $0.isFoil }
        }

        switch sortOrder {
        case .priceAscending:
            result.sort { $0.price < $1.price }
        case .priceDescending:
            result.sort { $0.price > $1.price }
        case .conditionBest:
            let conditionOrder = CardCondition.allCases
            result.sort {
                let i1 = conditionOrder.firstIndex(of: $0.condition) ?? 999
                let i2 = conditionOrder.firstIndex(of: $1.condition) ?? 999
                return i1 < i2
            }
        case .sellerRating:
            result.sort { ($0.seller.avgRating ?? 0) > ($1.seller.avgRating ?? 0) }
        }

        return result
    }

    // MARK: - Price Summary

    var lowestPrice: Double? {
        filteredArticles.map { $0.price }.min()
    }

    var availableListings: Int {
        filteredArticles.count
    }
}
