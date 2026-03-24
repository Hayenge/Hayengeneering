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

    // MARK: CardMarket state (search backend + listings)
    @Published var priceState: PriceState = .idle
    @Published var articles: [CardArticle] = []
    @Published var priceGuide: PriceGuide?
    @Published var selectedConditionFilter: CardCondition? = nil
    @Published var showFoilOnly: Bool = false
    @Published var sortOrder: SortOrder = .priceAscending

    // MARK: Price source visibility filters
    @Published var showCardMarketPrices: Bool = true
    @Published var showTCGPlayerPrices: Bool = true
    @Published var showPriceChartingPrices: Bool = true

    // MARK: TCGPlayer
    @Published var tcgPlayerPrice: TCGPlayerPrice? = nil
    @Published var tcgPlayerState: ExternalPriceState = .idle

    // MARK: PriceCharting
    @Published var priceChartingPrice: PriceChartingPrice? = nil
    @Published var priceChartingState: ExternalPriceState = .idle

    private let cardMarketService = CardMarketService.shared
    private let tcgPlayerService  = TCGPlayerService.shared
    private let priceChartingService = PriceChartingService.shared
    let card: Card

    enum SortOrder: String, CaseIterable {
        case priceAscending  = "Price: Low to High"
        case priceDescending = "Price: High to Low"
        case conditionBest   = "Best Condition First"
        case sellerRating    = "Seller Rating"
    }

    init(card: Card) {
        self.card = card
        if let cached = card.priceGuide {
            priceGuide = cached
        }
    }

    // MARK: - Data Loading

    func loadPrices() {
        guard case .idle = priceState else { return }
        priceState = .loading
        tcgPlayerState = .loading
        priceChartingState = .loading

        Task {
            async let cmTask: Void   = loadCardMarketPrices()
            async let tcgTask: Void  = loadTCGPlayerPrices()
            async let pcTask: Void   = loadPriceChartingPrices()
            _ = await (cmTask, tcgTask, pcTask)
        }
    }

    func refresh() {
        priceState = .idle
        articles = []
        tcgPlayerPrice = nil
        tcgPlayerState = .idle
        priceChartingPrice = nil
        priceChartingState = .idle
        loadPrices()
    }

    // MARK: - CardMarket (listings backend)

    private func loadCardMarketPrices() async {
        do {
            async let guideTask    = cardMarketService.getPriceGuide(productId: card.id)
            async let articlesTask = cardMarketService.getArticles(productId: card.id, maxResults: 50)
            let (guide, fetchedArticles) = try await (guideTask, articlesTask)
            priceGuide = guide
            articles   = fetchedArticles
            priceState = .loaded(guide, fetchedArticles)
        } catch CardMarketError.notConfigured {
            if let cached = card.priceGuide {
                priceState = .loaded(cached, [])
            } else {
                priceState = .error("Add your CardMarket API credentials to see marketplace listings.")
            }
        } catch {
            priceState = .error(error.localizedDescription)
        }
    }

    // MARK: - TCGPlayer

    private func loadTCGPlayerPrices() async {
        guard let categoryId = card.game.tcgPlayerCategoryId else {
            tcgPlayerState = .unavailable
            return
        }
        do {
            let price = try await tcgPlayerService.searchPrice(name: card.name, categoryId: categoryId)
            tcgPlayerPrice = price
            tcgPlayerState = price != nil ? .loaded : .notFound
        } catch TCGPlayerError.notConfigured {
            tcgPlayerState = .notConfigured
        } catch {
            tcgPlayerState = .error(error.localizedDescription)
        }
    }

    // MARK: - PriceCharting

    private func loadPriceChartingPrices() async {
        guard let consoleName = card.game.priceChartingConsoleName else {
            priceChartingState = .unavailable
            return
        }
        do {
            let price = try await priceChartingService.searchPrice(name: card.name, consoleName: consoleName)
            priceChartingPrice = price
            priceChartingState = price != nil ? .loaded : .notFound
        } catch PriceChartingError.notConfigured {
            priceChartingState = .notConfigured
        } catch {
            priceChartingState = .error(error.localizedDescription)
        }
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

    var lowestPrice: Double? {
        filteredArticles.map { $0.price }.min()
    }

    var availableListings: Int {
        filteredArticles.count
    }
}
